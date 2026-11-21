/// What a primitive tells the thread to do next.
///
/// The raw values are the ones tools use.
public enum ExitCode: UInt8, Sendable {
    case gotoTrue = 0
    case gotoFalse = 1
    case gotoTrueNextTick = 2
    case gotoFalseNextTick = 3
    case returnTrue = 4
    case returnFalse = 5
    case error = 6
    case continueNextTick = 7
    /// The primitive changed control flow itself (subroutine calls).
    case `continue` = 8
    /// Ends the current interaction at once.
    case interrupt = 9
    /// Takes the entity off the schedule for several ticks (idle primitives).
    case continueFutureTick = 10

    /// The name tools use, such as `GOTO_TRUE`.
    public var fsoCompatName: String {
        switch self {
        case .gotoTrue: "GOTO_TRUE"
        case .gotoFalse: "GOTO_FALSE"
        case .gotoTrueNextTick: "GOTO_TRUE_NEXT_TICK"
        case .gotoFalseNextTick: "GOTO_FALSE_NEXT_TICK"
        case .returnTrue: "RETURN_TRUE"
        case .returnFalse: "RETURN_FALSE"
        case .error: "ERROR"
        case .continueNextTick: "CONTINUE_NEXT_TICK"
        case .continue: "CONTINUE"
        case .interrupt: "INTERRUPT"
        case .continueFutureTick: "CONTINUE_FUTURE_TICK"
        }
    }
}
