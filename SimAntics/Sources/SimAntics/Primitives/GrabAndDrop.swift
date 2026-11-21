extension Primitives {
    /// Puts the stack object in the caller's hand, its first container slot (opcode 4).
    ///
    /// True if the object is there afterwards, false if the slot holds something else or doesn't
    /// exist. With no stack object it fails, with an error for the routine. 209 instructions on
    /// 1.1097.1.0.
    public enum Grab: Primitive {
        public static let name = "grab"
        public static let opcode: UInt8 = 4

        public static func execute(_ operand: EmptyOperand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let caller = frame.caller else { throw .nullReference("Grab has no caller") }
            guard let object = frame.stackObject else { throw .nullReference("Grab has no stack object") }
            return try caller.placeInSlot(object, slot: 0, cleanOld: true) ? .gotoTrue : .gotoFalse
        }
    }

    /// Puts down what the caller holds in its first slot, on a tile beside it (opcode 5).
    ///
    /// False with no slot or nothing in it; otherwise it tries the eight tiles around the
    /// caller's, at their centers, starting with the one it faces and then alternating either
    /// side of it, and goes true at the first where the object's group can be placed, facing the
    /// caller's way; false if none can. 21 instructions on 1.1097.1.0.
    public enum Drop: Primitive {
        public static let name = "drop"
        public static let opcode: UInt8 = 5

        /// North, then clockwise round the compass, in sixteenths of a tile.
        static let offsets: [(x: Int, y: Int)] = [(0, -16), (16, -16), (16, 0), (16, 16), (0, 16), (-16, 16), (-16, 0), (-16, -16)]

        public static func execute(_ operand: EmptyOperand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let caller = frame.caller else { throw .nullReference("Drop has no caller") }
            guard caller.totalSlots > 0, let held = caller.slot(0) else { return .gotoFalse }
            let facing = caller.direction.rawValue.trailingZeroBitCount
            let base = LotPosition.center(ofTileX: caller.position.tileX, y: caller.position.tileY, level: caller.position.level)
            for i in offsets.indices {
                let j = i % 2 == 1 ? offsets.count - 1 - i / 2 : i / 2
                let offset = offsets[(j + facing) % offsets.count]
                let target = LotPosition(x: Int16(truncatingIfNeeded: Int(base.x) + offset.x),
                                         y: Int16(truncatingIfNeeded: Int(base.y) + offset.y), level: base.level)
                if try frame.vm.place(held.group, at: target, facing: caller.direction).status == .success { return .gotoTrue }
            }
            return .gotoFalse
        }
    }
}
