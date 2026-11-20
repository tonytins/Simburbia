import Foundation
import Testing
import TSOContent
import TSOFiles
@testable import SimAntics

/// A file's animation with one motion of `frames` frames and these timed events.
private func fileAnimation(frames: UInt32 = 30, _ events: [(time: Int32, pairs: [(String, String)])]) -> TSOFiles.Animation {
    let timed = events.map { event in
        TSOFiles.Animation.TimedProperties(time: event.time, properties: .init(items: [event.pairs.map { .init(key: $0.0, value: $0.1) }]))
    }
    return TSOFiles.Animation(name: "test", duration: Float(frames) * 1000 / 30,
                              motions: [.init(boneName: "PELVIS", frameCount: frames, duration: 1_000, timedProperties: [timed])])
}

/// A clip of `frames` frames with `xevt`s at these times.
private func clip(frames: Int = 30, xevts: [(time: Int32, value: Int16)] = []) -> AnimationClip {
    AnimationClip(name: "test", frameCount: frames, events: xevts.map { AnimationClip.Event(time: $0.time, xevt: $0.value) })
}

/// The mock Sim, joined to the mock Sim lot, with nothing playing.
private func mockSim() throws -> (VM, Entity) {
    let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
    let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
    try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
    let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Dancer", persistID: 9, bodyOutfit: 0)))
    return (vm, sim)
}

@Suite struct AnimationClipTests {
    /// Events come out sorted by time, ties in file order, without negative times.
    @Test func sortsEventsByTimeAndDropsNegativeOnes() {
        let animation = fileAnimation([(600, [("xevt", "3")]), (-8_700, [("xevt", "9")]), (100, [("xevt", "1")]),
                                       (600, [("xevt", "4")]), (0, [("righthand", "2")])])
        let clip = AnimationClip(animation)
        #expect(clip.events.map(\.time) == [0, 100, 600, 600])
        #expect(clip.events.map(\.xevt) == [nil, 1, 3, 4])
        #expect(clip.events[0].rightHand == 2 && clip.frameCount == 30 && clip.name == "test")
    }

    /// Keys in any case, values trimmed of spaces and tabs; an empty value is skipped.
    @Test func readsKeysInAnyCaseAndTrimsValues() {
        let clip = AnimationClip(fileAnimation([(0, [("XEVT", "100")]), (10, [("xevt", "101\t")]), (20, [("xevt", "101 ")]),
                                                (30, [("xevt", "")]), (40, [("Sound", "chime"), ("LeftHand", "1")])]))
        #expect(clip.events.map(\.xevt) == [100, 101, 101, nil, nil])
        #expect(clip.events[4].sound == "chime" && clip.events[4].leftHand == 1)
    }

    /// MockInstall's stand: an `xevt` at 500 ms and a sound at 800.
    @Test func loadsTheMockStandFromTheInstallOnce() throws {
        let (vm, _) = try mockSim()
        let stand = try #require(try vm.animationClip(named: "MOCK-STAND"))
        #expect(stand.frameCount == 30 && stand.events.map(\.time) == [500, 800])
        #expect(stand.events[0].xevt == 1 && stand.events[1].sound == "mock_chime")
        #expect(vm.animationClips.keys.sorted() == ["mock-stand"])
        #expect(try vm.animationClip(named: "no-such-animation") == nil)
    }
}

@Suite struct AnimationPlaybackTests {
    /// A frame a tick; an event fires on the tick its time is reached (100 ms is frame 3).
    @Test func advancesAFrameATickAndFiresEventsWhenReached() throws {
        let (_, sim) = try mockSim()
        sim.sim.animations = [AnimationState(clip: clip(xevts: [(0, 7), (100, 101), (500, 2)]))]
        sim.advanceAnimations()
        #expect(sim.sim.animations[0].frame == 1 && sim.sim.animations[0].eventQueue == [7])
        sim.advanceAnimations()
        #expect(sim.sim.animations[0].eventQueue == [7])
        sim.advanceAnimations()
        #expect(sim.sim.animations[0].frame == 3 && sim.sim.animations[0].eventQueue == [7, 101])
        for _ in 4...15 { sim.advanceAnimations() }
        #expect(sim.sim.animations[0].eventQueue == [7, 101, 2])
        // Only events below 100 count as run.
        #expect(sim.sim.animations[0].eventsRun == 2)
    }

    /// A 30-frame animation ends once its next frame would be past the last: on frame 30, after
    /// 30 ticks, and it stays there.
    @Test func anAnimationEndsAtItsLastFrame() throws {
        let (_, sim) = try mockSim()
        sim.sim.animations = [AnimationState(clip: clip())]
        for _ in 1...29 { sim.advanceAnimations() }
        #expect(!sim.sim.animations[0].endReached && sim.sim.animations[0].frame == 29)
        sim.advanceAnimations()
        #expect(sim.sim.animations[0].endReached && sim.sim.animations[0].frame == 30)
        sim.advanceAnimations()
        #expect(sim.sim.animations[0].frame == 30)
    }

    /// A loop wraps by its length and fires its events again on every pass (DIFF-36).
    @Test func aLoopFiresItsEventsOnEveryPass() throws {
        let (_, sim) = try mockSim()
        sim.sim.animations = [AnimationState(clip: clip(frames: 10, xevts: [(100, 5)]), loops: true)]
        for _ in 1...30 { sim.advanceAnimations() }
        #expect(!sim.sim.animations[0].endReached)
        #expect(sim.sim.animations[0].eventQueue == [5, 5, 5])
        #expect(sim.sim.animations[0].frame < 10)
    }

    /// Backwards, from the last frame down, firing events at or after the current time.
    @Test func playsBackwards() throws {
        let (_, sim) = try mockSim()
        sim.sim.animations = [AnimationState(clip: clip(frames: 30, xevts: [(100, 1), (900, 2)]), playsBackwards: true)]
        #expect(sim.sim.animations[0].frame == 30)
        sim.advanceAnimations()
        #expect(sim.sim.animations[0].frame == 29 && sim.sim.animations[0].eventQueue.isEmpty)
        for _ in 1...2 { sim.advanceAnimations() }
        #expect(sim.sim.animations[0].frame == 27 && sim.sim.animations[0].eventQueue == [2])
        for _ in 1...24 { sim.advanceAnimations() }
        #expect(sim.sim.animations[0].frame == 3 && sim.sim.animations[0].eventQueue == [2, 1])
        for _ in 1...4 { sim.advanceAnimations() }
        #expect(sim.sim.animations[0].endReached)
    }

    /// Weight 0 holds an animation where it is; events from a second animation go to the first.
    @Test func weightlessAnimationsHoldAndEventsGoToTheFirst() throws {
        let (_, sim) = try mockSim()
        var held = AnimationState(clip: clip())
        held.weight = 0
        sim.sim.animations = [held, AnimationState(clip: clip(xevts: [(0, 4)]))]
        sim.advanceAnimations()
        #expect(sim.sim.animations[0].frame == 0 && sim.sim.animations[0].eventQueue == [4])
        #expect(sim.sim.animations[1].frame == 1 && sim.sim.animations[1].eventQueue.isEmpty)
    }

    /// Hand poses from events are kept for drawing.
    @Test func keepsHandPoses() throws {
        let (_, sim) = try mockSim()
        sim.sim.animations = [AnimationState(clip: AnimationClip(fileAnimation([(0, [("lefthand", "2"), ("righthand", "1")])])))]
        sim.advanceAnimations()
        #expect(sim.sim.leftHandPose == 2 && sim.sim.rightHandPose == 1)
    }

    /// Roadmap decision 8: frames are 32-bit floats, and these exact bits must come out on every
    /// platform. Ten steps of 0.7 are 6.999999, not 7, so the animation is still on frame 6.
    @Test func pinsFractionalFramesBitForBit() throws {
        let (_, sim) = try mockSim()
        var state = AnimationState(clip: clip(xevts: [(234, 1)]))
        state.speed = 0.7
        sim.sim.animations = [state]
        for _ in 1...10 { sim.advanceAnimations() }
        #expect(sim.sim.animations[0].frame.bitPattern == 0x40DF_FFFE)
        #expect(AnimationState.milliseconds(atFrame: sim.sim.animations[0].frame).bitPattern == 0x4369_5553)  // 233.3333
        #expect(sim.sim.animations[0].eventQueue.isEmpty)                                                   // 234 not reached
    }

    /// A frame that isn't finite, or is huge, counts as past an end rather than trapping.
    @Test func anUnreasonableFrameEndsTheAnimation() throws {
        let (_, sim) = try mockSim()
        for speed: Float in [.infinity, .nan, 3e9] {
            var state = AnimationState(clip: clip())
            state.speed = speed
            sim.sim.animations = [state]
            sim.advanceAnimations()
            #expect(sim.sim.animations[0].endReached, "\(speed)")
        }
    }

    /// The Sim's tick advances its animations, and the digest covers them, run after run alike.
    @Test func theSimsTickAdvancesThemAndTheDigestCoversThem() throws {
        func run() throws -> (String, String, Float) {
            let (vm, sim) = try mockSim()
            let before = StateDigest.hex(of: vm)
            sim.sim.animations = [AnimationState(clip: try #require(try vm.animationClip(named: "mock-dance")), loops: true)]
            for _ in 1...90 { vm.tick() }
            return (before, StateDigest.hex(of: vm), sim.sim.animations[0].frame)
        }
        let first = try run(), second = try run()
        #expect(first.2 > 0)
        #expect(first.0 != first.1)
        #expect(first == second)
    }
}

/// What TSO's own animations need of the clip (1.1097.1.0, the base game, and the beta alike).
@Suite(.enabled(if: gameDirectory != nil, "TSO_GAME_DIR is not set"))
struct RealAnimationClipTests {
    let content: GameContent

    init() throws {
        content = try GameContent(.init(gameDirectory: try required(gameDirectory)))
    }

    private func clip(_ name: String) throws -> AnimationClip {
        AnimationClip(try required(try content.animations.animation(named: name + ".anim"), name))
    }

    /// The tub's getting in has a capital `XEVT` and an `xevt` ending in a tab; both count.
    @Test func theTubsEventsCountInAnyCaseAndWithATab() throws {
        let xevts = try clip("a2o-tub1-getinr").events.compactMap(\.xevt)
        #expect(xevts.contains(100) && xevts.contains(101))
    }

    /// A dog's fetch has negative times, which are dropped, and the rest come out in order.
    @Test func dropsNegativeTimesAndSorts() throws {
        let animation = try required(try content.animations.animation(named: "a2d-fun-fetch-throw.anim"))
        #expect(animation.timedProperties.contains { $0.time < 0 })
        let events = AnimationClip(animation).events
        #expect(!events.isEmpty && events.allSatisfy { $0.time >= 0 })
        #expect(events.map(\.time) == events.map(\.time).sorted())
    }

    /// The reach animations' empty `xevt`s are skipped, not read as 0.
    @Test func skipsAnEmptyEvent() throws {
        let animation = try required(try content.animations.animation(named: "a2o-reach-tableht-aroundchairl.anim"))
        let empty = animation.timedProperties.filter { AnimationClip.value($0.properties, "xevt") == "" }.count
        #expect(empty > 0)
        let clip = AnimationClip(animation)
        #expect(clip.events.filter { $0.xevt == nil }.count >= empty)
    }
}
