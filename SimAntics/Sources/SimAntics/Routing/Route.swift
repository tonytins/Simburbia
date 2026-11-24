/// Why a route failed, as a routine reads it from the Sim's person data `RouteResult`; the values
/// are the ones content compares against.
public enum RouteFailure: Int16, Sendable, Equatable {
    case unknown = 1
    case noRoomRoute
    /// No path reaches any goal.
    case noPath
    /// The Sim's interaction was cancelled on the way.
    case interrupted
    case cantSit
    /// Something stands where the Sim would stand.
    case cantStand
    /// None of the goals is a place a Sim can stand.
    case noValidGoals
    case destinationTileOccupied
    case destinationChairOccupied
    case noChair
    case wallInWay
    case altitudesDontMatch
    /// A Sim stands where this one would.
    case destinationTileOccupiedByPerson
}

/// A place a route may end: where, which way the Sim faces there (in radians clockwise from
/// north; `nil` for any way), which of the slot's directions it's in, and the chair the Sim sits
/// in there, if any.
public struct RouteGoal {
    public var position: LotPosition
    public var facing: Double?
    public var directions: Int16
    public var chair: Entity?

    public init(position: LotPosition, facing: Double? = nil, directions: Int16 = 1, chair: Entity? = nil) {
        self.position = position
        self.facing = facing
        self.directions = directions
        self.chair = chair
    }

    /// A spot a routing slot found.
    public init(_ spot: RouteSpot) {
        self.init(position: spot.position, facing: spot.facing, directions: Int16(truncatingIfNeeded: spot.directions.rawValue),
                  chair: spot.chair)
    }
}

/// A Sim on its way somewhere: the stack frame routing primitives push, which runs a route
/// instead of instructions, a step a tick, until the Sim arrives (true to the routine below) or
/// the route fails (false, with why in the Sim's person data `RouteResult`).
///
/// **Walking.** The route is found with ``VM/findPath(for:from:to:)`` to the nearest goal, then
/// walked leg by leg. A Sim turning 45° or more first plays its turn animation (from its walk
/// table: 180° at 4 and 5, 90° at 6 and 7, 45° at 8 and 9, left then right) and faces the new way
/// when it ends. It walks at 0.05 tiles a tick at full speed, three times that with a walk style
/// of 1 (running), working up to it over 8 ticks and slowing over the last 28 move frames
/// (each leg of d sixteenths is d × 10 move frames, 8 a tick at full speed). That is the pace of
/// its walk animations: the walk and half walk, two to one, played at 1.5 times, cover about 1.47
/// tiles a second (taking the animations' 3 units a tile); running covers about 4.6. Its animations
/// blend from standing (walk table 3) into the walk (20, or 21 running) and half walk (25) as it
/// speeds up.
///
/// **Arriving.** The Sim turns to the goal's facing (with a turn animation for 45° or more), stands
/// (walk table 3, looping), and its person data `RouteEntryFlags` takes the goal's directions. At a
/// chair, it runs the chair's sit entry point (26), and the route returns what that returns.
///
/// **Trouble.** A step that can't place the Sim (something moved into the way) plans again from
/// where it is, three times at most, then fails with no path. A cancelled interaction stops the
/// walk with "interrupted", unless the Sim is non-interruptable. A route that fails, when it calls
/// failure trees, runs the global's route failure feedback (routine 398) with the reason and what
/// was in the way as its arguments, then returns false.
public final class RoutingFrame {
    /// Where the route may end, best first.
    public var goals: [RouteGoal]
    /// Whether a failure runs the global's route failure feedback.
    public let callsFailureTree: Bool
    /// A turn alone, toward this facing, instead of a walk (Look Towards).
    let turnOnly: Double?

    private enum State: Equatable {
        case planning
        case turning(toward: Double, thenWalks: Bool)
        case walking
        case sitting
        case failing(RouteFailure)
        case done
    }

    private var state = State.planning
    private var waypoints: [LotPosition] = []
    private var leg = 1
    private var previous = LotPosition.outOfWorld
    private var moveFrames = 0
    private var moveTotal = 1
    private var velocity = 0
    private var goal: RouteGoal?
    private var retries = 3
    /// Why the route can't start, found before it was pushed (a slot with no spots).
    private var initialFailure: (RouteFailure, Entity?)?

    /// The global's routine a failed route runs to show it, given the reason and the blocker.
    static let failureTree: UInt16 = 398
    /// The global's walk table entries routing plays.
    enum Walk {
        static let stand = 3, walk = 20, run = 21, halfWalk = 25
        static let turn180 = 4, turn90 = 6, turn45 = 8
    }

    public init(goals: [RouteGoal], callsFailureTree: Bool = false) {
        self.goals = goals
        self.callsFailureTree = callsFailureTree
        turnOnly = nil
    }

    /// A route that fails as soon as it runs, for a slot that offered nowhere to go.
    init(failing failure: RouteFailure, blocker: Entity?, callsFailureTree: Bool) {
        goals = []
        self.callsFailureTree = callsFailureTree
        turnOnly = nil
        initialFailure = (failure, blocker)
    }

    /// A turn on the spot toward a facing, in radians clockwise from north.
    init(turningToward facing: Double) {
        goals = []
        callsFailureTree = false
        turnOnly = facing
    }

    /// What one run of the frame did.
    enum Step: Equatable {
        /// Still on the way; runs again next tick.
        case walking
        /// Pushed a routine (a chair's sit, or the failure tree); runs again when it returns.
        case called
        case arrived
        case failed(RouteFailure)
    }

    /// Runs the route a step for `sim`, on its thread.
    func step(for sim: Entity, on thread: VMThread) throws(SimAnticsError) -> Step {
        let vm = sim.vm
        switch state {
        case .done:
            return thread.lastExitCode == .returnTrue ? .arrived : .failed(.cantSit)
        case .sitting:
            state = .done
            return thread.lastExitCode == .returnTrue ? .arrived : .failed(.cantSit)
        case .failing(let failure):
            return .failed(failure)
        case .planning:
            if let turn = turnOnly {
                return try startTurn(sim, toward: turn, thenWalks: false) ? .walking : finish(sim, on: thread)
            }
            if let (failure, blocker) = initialFailure { return try fail(sim, failure, blocker: blocker, on: thread) }
            if Self.isCancelled(sim) { return try fail(sim, .interrupted, blocker: nil, on: thread) }
            switch try vm.findPath(for: sim, from: sim.position, to: goals) {
            case .failure(let failure):
                return try fail(sim, failure, blocker: nil, on: thread)
            case .success(let path):
                waypoints = path.waypoints
                goal = goals[path.goal]
                previous = waypoints[0]
                leg = 1
                guard waypoints.count > 1 else { return try arrive(sim, on: thread) }
                return try startLeg(sim, firstLeg: true, on: thread)
            }
        case .turning(let target, let thenWalks):
            guard sim.sim.animations.first?.endReached ?? true else { return .walking }
            sim.direction = Direction(radians: target)
            if thenWalks {
                startWalkAnimations(sim)
                state = .walking
                return .walking
            }
            return try finish(sim, on: thread)
        case .walking:
            if Self.isCancelled(sim) {
                standStill(sim)
                return try fail(sim, .interrupted, blocker: nil, on: thread)
            }
            let lastLeg = leg == waypoints.count - 1
            if lastLeg && moveTotal - moveFrames <= 28 {
                velocity = max(1, velocity - 1)
            } else {
                velocity = min(8, velocity + 1)
            }
            moveFrames = min(moveTotal, moveFrames + velocity)
            let target = waypoints[leg]
            let x = Int(previous.x) + (Int(target.x) - Int(previous.x)) * moveFrames / moveTotal
            let y = Int(previous.y) + (Int(target.y) - Int(previous.y)) * moveFrames / moveTotal
            let next = LotPosition(x: Int16(truncatingIfNeeded: x), y: Int16(truncatingIfNeeded: y), level: previous.level)
            blendWalk(sim)
            let placed = try vm.place(sim.group, at: next, facing: sim.direction)
            guard placed.status == .success else {
                retries -= 1
                guard retries > 0 else { return try fail(sim, .noPath, blocker: placed.object, on: thread) }
                state = .planning
                return .walking
            }
            guard moveFrames >= moveTotal else { return .walking }
            previous = target
            leg += 1
            guard leg < waypoints.count else { return try arrive(sim, on: thread) }
            return try startLeg(sim, firstLeg: false, on: thread)
        }
    }

    // MARK: Walking

    /// Faces the next leg and starts it: a turn animation first for the first leg's turn of 45° or
    /// more; later legs turn as they go.
    private func startLeg(_ sim: Entity, firstLeg: Bool, on thread: VMThread) throws(SimAnticsError) -> Step {
        let target = waypoints[leg]
        let facing = DeterministicMath.atan2(Double(Int(target.x) - Int(previous.x)), -Double(Int(target.y) - Int(previous.y)))
        moveFrames = 0
        moveTotal = max(1, previous.distance(to: target) * 10 / (Self.walkStyle(sim) == 1 ? 3 : 1))
        if firstLeg {
            velocity = 0
            if try startTurn(sim, toward: facing, thenWalks: true) { return .walking }
            startWalkAnimations(sim)
        }
        sim.direction = Direction(radians: facing)
        state = .walking
        return .walking
    }

    /// Plays the turn animation toward a facing, if the turn is 45° or more; `false` if it isn't.
    private func startTurn(_ sim: Entity, toward target: Double, thenWalks: Bool) throws(SimAnticsError) -> Bool {
        let difference = VM.normalized(target - sim.radians)
        let size = abs(difference)
        let index: Int
        if size >= DeterministicMath.pi - 0.01 {
            index = Walk.turn180
        } else if size >= DeterministicMath.halfPi - 0.01 {
            index = Walk.turn90
        } else if size >= DeterministicMath.quarterPi - 0.01 {
            index = Walk.turn45
        } else {
            sim.direction = Direction(radians: target)
            return false
        }
        guard let name = sim.sim.walkAnimations.element(at: index + (difference > 0 ? 0 : 1)) ?? nil,
              let clip = try sim.vm.animationClip(named: name) else {
            sim.direction = Direction(radians: target)
            return false
        }
        var turn = AnimationState(clip: clip)
        if Self.walkStyle(sim) == 1 { turn.speed = 2 }
        sim.sim.animations = [turn]
        state = .turning(toward: target, thenWalks: thenWalks)
        return true
    }

    /// The standing pose and the two walks, blended by speed as the Sim walks.
    private func startWalkAnimations(_ sim: Entity) {
        let running = Self.walkStyle(sim) == 1
        let names = [Walk.stand, running ? Walk.run : Walk.walk, running ? Walk.run : Walk.halfWalk].map {
            sim.sim.walkAnimations.element(at: $0) ?? nil
        }
        var states: [AnimationState] = []
        for (index, name) in names.enumerated() {
            guard let name, let clip = try? sim.vm.animationClip(named: name) else { continue }
            var state = AnimationState(clip: clip, loops: true)
            if index > 0 { state.speed = 1.5 }
            states.append(state)
        }
        sim.sim.animations = states
        blendWalk(sim)
    }

    /// Standing fades out and the walks in as the Sim speeds up, the walk two parts to the half
    /// walk's one.
    private func blendWalk(_ sim: Entity) {
        let weights: [Float] = [Float(8 - velocity) / 8, Float(velocity) / 8 * 0.66, Float(velocity) / 8 * 0.33]
        for index in sim.sim.animations.indices where index < weights.count { sim.sim.animations[index].weight = weights[index] }
    }

    /// The standing pose, looping.
    private func standStill(_ sim: Entity) {
        guard let name = sim.sim.walkAnimations.element(at: Walk.stand) ?? nil,
              let clip = try? sim.vm.animationClip(named: name) else {
            sim.sim.animations = []
            return
        }
        sim.sim.animations = [AnimationState(clip: clip, loops: true)]
    }

    // MARK: Arriving and failing

    private func arrive(_ sim: Entity, on thread: VMThread) throws(SimAnticsError) -> Step {
        sim.personData[PersonData.routeEntryFlags] = goal?.directions ?? 0
        if let facing = goal?.facing, try startTurn(sim, toward: facing, thenWalks: false) { return .walking }
        return try finish(sim, on: thread)
    }

    /// Stands the Sim, then sits it if the goal is a chair.
    private func finish(_ sim: Entity, on thread: VMThread) throws(SimAnticsError) -> Step {
        if let facing = turnOnly ?? goal?.facing { sim.direction = Direction(radians: facing) }
        standStill(sim)
        guard let chair = goal?.chair else { return .arrived }
        guard let table = chair.entryPoints, table.count > 26, table[26].actionFunction != 0,
              let routine = try sim.vm.routine(opcode: table[26].actionFunction, codeOwner: chair.object),
              let top = thread.stack.last else { return .arrived }
        let sit = StackFrame(thread: thread, routine: routine, caller: sim, callee: chair, codeOwner: chair.object)
        sit.stackObject = chair
        sit.isActionTree = top.isActionTree
        sit.arguments = [0, 0, 0, 0]
        thread.push(sit)
        state = .sitting
        return .called
    }

    private func fail(_ sim: Entity, _ failure: RouteFailure, blocker: Entity?, on thread: VMThread) throws(SimAnticsError) -> Step {
        sim.personData[PersonData.routeResult] = failure.rawValue
        guard callsFailureTree, let top = thread.stack.last,
              let routine = try sim.vm.routine(opcode: Self.failureTree, codeOwner: top.codeOwner) else { return .failed(failure) }
        let feedback = StackFrame(thread: thread, routine: routine, caller: top.caller, callee: top.callee, codeOwner: top.codeOwner)
        feedback.stackObject = top.stackObject
        feedback.isActionTree = top.isActionTree
        feedback.arguments = [failure.rawValue, blocker?.objectID ?? 0, 0, 0]
        thread.push(feedback)
        state = .failing(failure)
        return .called
    }

    /// Whether the Sim's interaction was cancelled and it may stop.
    static func isCancelled(_ sim: Entity) -> Bool {
        sim.hasFlag(EntityFlag.interactionCanceled) && sim.personData[PersonData.nonInterruptable] == 0
    }

    /// The Sim's walk style (object data): 1 runs.
    static func walkStyle(_ sim: Entity) -> Int16 {
        sim.objectData[Int(ObjectVariable.walkStyle.rawValue)]
    }
}

extension Routine {
    /// What a routing frame shows as its routine: ID 0, named "routing", with no instructions.
    static let routing = Routine(id: 0, name: "routing", instructions: [])
}

extension VMThread {
    /// Pushes a route on top of `frame`, for `frame`'s caller, with its callee, stack object,
    /// and code owner. It runs from the next instruction on.
    public func pushRoute(_ route: RoutingFrame, from frame: StackFrame) {
        let routing = StackFrame(thread: self, routine: .routing, caller: frame.caller, callee: frame.callee,
                                 codeOwner: frame.codeOwner)
        routing.stackObject = frame.stackObject
        routing.isActionTree = frame.isActionTree
        routing.route = route
        stack.append(routing)
    }
}
