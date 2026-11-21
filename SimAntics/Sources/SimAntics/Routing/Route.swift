/// Why a route failed, as a routine reads it from the Sim's `PrimitiveResult` (object data);
/// the values are the ones content compares against.
public enum RouteFailure: Int16, Sendable, Equatable {
    case unknown = 1
    case noRoomRoute
    /// No path reaches any goal.
    case noPath
    /// The Sim's interaction was cancelled on the way.
    case interrupted
    case cantSit
    /// Something stands where the Sim would stand; it's named in `PrimitiveResultID`.
    case cantStand
    /// None of the goals is a place a Sim can stand.
    case noValidGoals
    case destinationTileOccupied
    case destinationChairOccupied
    case noChair
    case wallInWay
    case altitudesDontMatch
    /// A Sim stands where this one would; it's named in `PrimitiveResultID`.
    case destinationTileOccupiedByPerson
}

/// A place a route may end: where, and which way the Sim faces there, if it matters.
public struct RouteGoal: Sendable, Equatable {
    public var position: LotPosition
    public var facing: Direction?

    public init(position: LotPosition, facing: Direction? = nil) {
        self.position = position
        self.facing = facing
    }
}

/// A Sim on its way somewhere: the stack frame routing primitives push, which runs a route
/// instead of instructions until the Sim arrives (true) or the route fails (false, with why in
/// the Sim's `PrimitiveResult` and what was in the way in `PrimitiveResultID`).
///
/// **Scaffolding (phase E1).** A route with no goals fails at once, as no valid goals; finding the
/// path (E3) and walking it (E4) come later, so a route with goals is unsupported until then.
public final class RoutingFrame {
    /// Where the route may end, best first.
    public var goals: [RouteGoal]

    public init(goals: [RouteGoal]) {
        self.goals = goals
    }

    /// What one run of the frame did.
    enum Step: Equatable {
        /// Still on the way; runs again next tick.
        case walking
        case arrived
        case failed(RouteFailure, blocker: Int16)
    }

    /// Runs the route a step for `sim`.
    func step(for sim: Entity) throws(SimAnticsError) -> Step {
        guard !goals.isEmpty else { return .failed(.noValidGoals, blocker: 0) }
        throw .unsupported("walking a route (phase E4)")
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
