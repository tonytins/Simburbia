extension Primitives {
    /// Moves the caller straight to a place by an object, without walking there (opcode 46).
    ///
    /// **A stand-in until routing (phase E).** Only mode 2, "be in front of the stack object", runs:
    /// it's what a Sim needs to fall asleep on the floor, which every Sim reaches when its energy
    /// runs out on a lot without a bed. It moves the caller to the point one tile in front of the
    /// stack object (16 units along its facing; 11 and 11 on a diagonal), on its level, keeping
    /// the caller's facing, and goes true. If the caller can't be placed there, it records what
    /// was in the way in object data `PrimitiveResultID` (2 in `PrimitiveResult` when it's off the
    /// lot) and goes false. Routing's slot search, which also tries other spots, comes with phase E,
    /// as does flag 2, which asks a Sim standing there to move.
    ///
    /// 1.1097.1.0's 248 Snap instructions use mode 3 (a routing slot by number, 188), 4 (a global
    /// routing slot, 36), 0 (a slot from a parameter, 11), 1 (be contained, 6), and 2 (6, plus the
    /// global's falling on the floor). The other modes are unsupported.
    public enum Snap: Primitive {
        public static let name = "snap"
        public static let opcode: UInt8 = 46

        public struct Operand: PrimitiveOperand, Equatable {
            public var index: UInt16
            /// How ``index`` picks the slot: 2 is in front of the stack object.
            public var mode: UInt16
            /// 1 origin only, 2 ask a Sim in the way to move, 4 use footprint extensions.
            public var flags: UInt8

            public init(index: UInt16 = 0, mode: UInt16, flags: UInt8 = 0) {
                self.index = index
                self.mode = mode
                self.flags = flags
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                index = reader.uint16()
                mode = reader.uint16()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(index)
                    writer.uint16(mode)
                    writer.uint8(flags)
                }
            }
        }

        /// One tile in front, by facing from north clockwise, in sixteenths of a tile.
        static let inFront: [(x: Int, y: Int)] = [(0, -16), (11, -11), (16, 0), (11, 11), (0, 16), (-11, 11), (-16, 0), (-11, -11)]

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard operand.mode == 2 else { throw .unsupported("Snap mode \(operand.mode) (routing, phase E)") }
            guard let caller = frame.caller else { throw .nullReference("Snap has no caller") }
            guard let target = frame.stackObject else { throw .nullReference("Snap has no stack object") }
            let facing = target.direction.rawValue.trailingZeroBitCount
            guard inFront.indices.contains(facing) else { throw .indexOutOfRange("direction \(target.direction.rawValue)") }
            let offset = inFront[facing]
            let spot = LotPosition(x: Int16(truncatingIfNeeded: Int(target.position.x) + offset.x),
                                   y: Int16(truncatingIfNeeded: Int(target.position.y) + offset.y), level: target.position.level)
            let result = try frame.vm.place(caller.group, at: spot, facing: caller.direction)
            guard result.status == .success else {
                if result.status == .locationOutOfBounds {
                    try caller.setValue(2, of: ObjectVariable.primitiveResult.rawValue)
                }
                try caller.setValue(result.object?.objectID ?? 0, of: ObjectVariable.primitiveResultID.rawValue)
                return .gotoFalse
            }
            return .gotoTrue
        }
    }
}
