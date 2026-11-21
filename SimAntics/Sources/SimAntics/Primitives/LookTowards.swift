extension Primitives {
    /// Turns the calling Sim's head or body (opcode 22).
    ///
    /// Of 1.1097.1.0's 387 instructions, modes 0 and 1 go true at once. Mode 0 (100) turns the head
    /// toward an object, which only drawing shows. Mode 1 (42), turning the body toward the camera,
    /// does nothing in TSO, whose camera isn't a place on the lot; it's in the global's refusals
    /// ("Refuse Moody?" and "Refuse Fun Object?"), which turn a Sim away from what it won't do.
    /// Modes 2 to 5 (245) turn the body toward or away from the stack object, or the middle of its
    /// parts, with a routing frame; they come with routing (phase E) and are unsupported until
    /// then. A caller that isn't a Sim fails, with an error for the routine.
    public enum LookTowards: Primitive {
        public static let name = "look_towards"
        public static let opcode: UInt8 = 22

        public struct Operand: PrimitiveOperand, Equatable {
            /// 0 head toward the stack object, 1 body toward the camera, 2 and 3 body toward and
            /// away from the stack object, 4 and 5 toward and away from the middle of its parts.
            public var mode: UInt8

            public init(mode: UInt8) { self.mode = mode }
            public init(bytes: [UInt8]) { mode = bytes.first ?? 0 }
            public func encoded() -> [UInt8] { OperandWriter.bytes { $0.uint8(mode) } }
        }

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let caller = frame.caller, caller.isAvatar else { throw .invalidCast("Look Towards' caller isn't a Sim") }
            switch operand.mode {
            case 0, 1: return .gotoTrue
            default: throw .unsupported("Look Towards mode \(operand.mode) (routing, phase E)")
            }
        }
    }
}
