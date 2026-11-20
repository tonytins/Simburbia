import Foundation
import TSOContent
import TSOFiles

/// An animation as the VM plays it: its length and its events, sorted by time.
///
/// Built from TSOFiles' ``TSOFiles/Animation``, keeping only what the simulation needs (drawing
/// a Sim needs the rest). Its events are each motion's timed properties, which the VM reads
/// in time order:
///
/// - **Sorted by time, ties in file order.** 86 of 1.1097.1.0's animations list events out of
///   time order, since each motion lists its own. FreeSO means to sort them and doesn't (its
///   `OrderBy` result is dropped), so it fires some late; plumbob-engine sorts them.
/// - **Negative times are dropped.** 1,653 events in 363 animations, mostly pets' and
///   children's, have negative times. Neither FreeSO (which reads them as unsigned, so they wait
///   forever) nor plumbob-engine fires them. **Unverified** for TSO's own client.
/// - **Keys match in any letter case**, as plumbob-engine matches them, so the tub's `XEVT`
///   counts. A value is trimmed of spaces and tabs first (six of TSO's `xevt`s end with one),
///   as .NET's `short.Parse` trims them; an empty or unparsable value is skipped, a tolerance
///   two of TSO's reach animations need (FreeSO's `short.Parse` throws on them).
///
/// Times past the last frame never fire, in FreeSO or plumbob-engine; TSO has 1,683 of them.
public struct AnimationClip: Sendable, Equatable {
    /// One timed event: what an animation does at a time, in the properties the VM reads.
    public struct Event: Sendable, Equatable {
        /// Milliseconds from the start, 0 or more.
        public var time: Int32
        /// An event for the routine that's animating (`xevt`).
        public var xevt: Int16?
        /// Hand poses, which only drawing reads (`lefthand`, `righthand`).
        public var leftHand: Int16?
        public var rightHand: Int16?
        /// A sound to play, which only a client with audio plays (`sound`).
        public var sound: String?
    }

    /// The name in the animation's file, which the state digest uses.
    public var name: String
    /// The longest motion's frames (FreeSO's `NumFrames`).
    public var frameCount: Int
    /// Events with times of 0 or more, sorted by time, ties in file order.
    public var events: [Event]

    public init(_ animation: TSOFiles.Animation) {
        name = animation.name
        frameCount = Int(animation.frameCount)
        let timed = animation.timedProperties.enumerated().filter { $0.element.time >= 0 }
        // Sorted by time, then by place in the file, so ties keep their order.
        events = timed.sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map { _, item in
            Event(time: item.time, xevt: Self.number(item.properties, "xevt"), leftHand: Self.number(item.properties, "lefthand"),
                  rightHand: Self.number(item.properties, "righthand"), sound: Self.value(item.properties, "sound"))
        }
    }

    public init(name: String, frameCount: Int, events: [Event]) {
        self.name = name
        self.frameCount = frameCount
        self.events = events
    }

    /// The first value for `key` in any letter case.
    static func value(_ properties: TSOFiles.Animation.PropertyList, _ key: String) -> String? {
        for item in properties.items {
            if let property = item.first(where: { $0.key.lowercased() == key }) { return property.value }
        }
        return nil
    }

    /// The value for `key` as a number, trimmed of spaces and tabs, or `nil` if it isn't one.
    static func number(_ properties: TSOFiles.Animation.PropertyList, _ key: String) -> Int16? {
        value(properties, key).flatMap { Int16($0.trimmingCharacters(in: .whitespaces)) }
    }
}

extension AnimationClip.Event {
    public init(time: Int32, xevt: Int16? = nil) {
        self.init(time: time, xevt: xevt, leftHand: nil, rightHand: nil, sound: nil)
    }
}

/// One animation a Sim is playing (FreeSO's `VMAnimationState`).
///
/// Frames, speed, and weight are 32-bit floats, as the files and FreeSO keep them: the first
/// floats that feed simulation state (roadmap decision 8). Adding a speed of 1 to a whole frame
/// is exact; a test pins the values a fractional speed gives, so each platform CI runs on must
/// agree.
public struct AnimationState: Sendable, Equatable {
    public var clip: AnimationClip
    public var frame: Float
    public var speed: Float = 1
    /// For blending several animations; one with weight 0 doesn't advance.
    public var weight: Float = 1
    public var playsBackwards: Bool
    public var loops: Bool
    public var endReached = false
    /// `xevt`s below 100 fired so far (FreeSO's `EventsRun`, a byte that wraps).
    public var eventsRun: UInt8 = 0
    /// `xevt`s fired and not yet heard by the routine, oldest first.
    public var eventQueue: [Int16] = []
    /// The next event to fire: an index into the clip's events, counting down when backwards.
    public var nextEvent: Int

    /// Starts at the first frame, or at the last when backwards.
    public init(clip: AnimationClip, playsBackwards: Bool = false, loops: Bool = false) {
        self.clip = clip
        self.playsBackwards = playsBackwards
        self.loops = loops
        frame = playsBackwards ? Float(clip.frameCount) : 0
        nextEvent = playsBackwards ? clip.events.count - 1 : 0
    }

    /// The milliseconds a frame stands for: 30 frames a second, as FreeSO times events, which
    /// TSO's files agree with (their durations are a frame or so short of their frames' time).
    static func milliseconds(atFrame frame: Float) -> Float {
        frame * 1000 / 30
    }

    /// Whether playback has run off either end (`Animator.SilentFrameProgress`): the frame,
    /// truncated, is below 0 or its next frame is past the last. A frame that isn't finite or is
    /// past any animation's length counts as off the end, rather than trapping on the conversion.
    var isPastAnEnd: Bool {
        guard frame.isFinite, abs(frame) < 1_000_000_000 else { return true }
        let whole = Int(frame.rounded(.towardZero))
        return whole < 0 || whole + 1 > clip.frameCount
    }
}

extension Entity {
    /// Advances each of a Sim's animations a tick, as `VMAvatar.Tick` does, firing the events
    /// it passes.
    ///
    /// An animation that hasn't ended and has weight moves its frame by its speed, then fires
    /// every event whose time it has reached: forward, times at or before the current time;
    /// backward, times at or after it. Then, past either end, a looping animation wraps by its
    /// length and arms its events again, and any other ends.
    ///
    /// Where it differs from FreeSO: a looping animation's events fire on every pass, as in
    /// plumbob-engine; FreeSO fires them on the first pass only, since it removes each event as
    /// it fires and never puts them back (DIFF-36). 175 of 1.1097.1.0's looping animations have
    /// `xevt`s.
    ///
    /// An `xevt` goes to the Sim's first animation, as FreeSO's `CurrentAnimationState` takes
    /// it, and counts toward its ``AnimationState/eventsRun`` when below 100. Hand poses are kept
    /// for drawing; sounds wait for a client with audio. The carry animation doesn't advance, as
    /// in FreeSO ("I don't think any of them are animated").
    func advanceAnimations() {
        for index in sim.animations.indices {
            var fired: [AnimationClip.Event] = []
            var state = sim.animations[index]
            if !state.endReached, state.weight != 0 {
                state.frame += state.playsBackwards ? -state.speed : state.speed
                let now = AnimationState.milliseconds(atFrame: state.frame)
                let events = state.clip.events
                if state.playsBackwards {
                    while state.nextEvent >= 0, state.nextEvent < events.count, Float(events[state.nextEvent].time) >= now {
                        fired.append(events[state.nextEvent])
                        state.nextEvent -= 1
                    }
                } else {
                    while state.nextEvent >= 0, state.nextEvent < events.count, Float(events[state.nextEvent].time) <= now {
                        fired.append(events[state.nextEvent])
                        state.nextEvent += 1
                    }
                }
            }
            // Stored before the events, which go to the first animation, perhaps this one.
            sim.animations[index] = state
            for event in fired { handle(event) }
            if sim.animations[index].isPastAnEnd {
                if sim.animations[index].loops {
                    let length = Float(sim.animations[index].clip.frameCount)
                    sim.animations[index].frame += sim.animations[index].playsBackwards ? length : -length
                    sim.animations[index].nextEvent = sim.animations[index].playsBackwards ? sim.animations[index].clip.events.count - 1 : 0
                } else {
                    sim.animations[index].endReached = true
                }
            }
        }
    }

    private func handle(_ event: AnimationClip.Event) {
        if let xevt = event.xevt, !sim.animations.isEmpty {
            sim.animations[0].eventQueue.append(xevt)
            if xevt < 100 { sim.animations[0].eventsRun &+= 1 }
        }
        if let leftHand = event.leftHand { sim.leftHandPose = leftHand }
        if let rightHand = event.rightHand { sim.rightHandPose = rightHand }
    }
}

extension VM {
    /// The animation with this name (without `.anim`), in any letter case, decoded once and
    /// kept for the life of the VM, or `nil` if the install has none.
    ///
    /// - Throws: ``SimAnticsError/content(_:)`` if its file can't be read.
    public func animationClip(named name: String) throws(SimAnticsError) -> AnimationClip? {
        let key = name.lowercased()
        if let clip = animationClips[key] { return clip }
        let animation: TSOFiles.Animation?
        do {
            animation = try content.animations.animation(named: key + ".anim")
        } catch {
            throw .content(error)
        }
        guard let animation else { return nil }
        let clip = AnimationClip(animation)
        animationClips[key] = clip
        return clip
    }
}
