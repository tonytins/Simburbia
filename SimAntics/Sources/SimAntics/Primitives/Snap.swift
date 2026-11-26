import TSOFiles

extension Primitives {
    /// Moves the caller straight to a place by the stack object, without walking there
    /// (opcode 46).
    ///
    /// The place comes from a routing slot (``VM/findSpots(for:around:for:)``), chosen by the mode:
    ///
    /// - **0:** the stack object's routing slot numbered by the parameter the operand names.
    /// - **1:** no slot: the caller goes into the stack object's container slot 0, true if it fits.
    /// - **2:** in front of the stack object: a slot one tile (16 sixteenths) out, in its north
    ///   direction, turned with it. A Sim falling asleep on the floor snaps in front of itself.
    /// - **3:** the stack object's routing slot the operand numbers.
    /// - **4:** the global's routing slot the operand numbers (`SLOT` 100).
    ///
    /// A slot that snaps into one of the object's slots (its snap target) puts the caller there,
    /// facing the slot's way when it snaps to a direction. Otherwise the caller moves to the slot's
    /// best spot, facing that spot's way when the slot snaps to a direction, else keeping its own,
    /// and it's true. With no spot, or a spot the caller can't be placed in after all, it's false:
    /// object data `PrimitiveResult` is 2 when there's no valid goal, or the spot is off the lot,
    /// and `PrimitiveResultID` names what was in the way. With flag 2, a Sim in the way is asked to
    /// move (``VM/shoo(_:by:)``), and it's still false. A slot number past the slots is false. No stack object fails, with
    /// an error for the routine.
    ///
    /// 1.1097.1.0's 248 Snap instructions use mode 3 (188), 4 (36), 0 (11), 1 (6), and 2 (6, and
    /// the global's falling on the floor).
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

        /// The slot mode 2 uses: one tile out, in the object's north direction.
        static let inFront = SLOT.Slot(type: 3, standing: 1, flags: .north, minProximity: 16)

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let caller = frame.caller else { throw .nullReference("Snap has no caller") }
            guard let object = frame.stackObject else { throw .nullReference("Snap has no stack object") }
            let slot: SLOT.Slot?
            switch operand.mode {
            case 0:
                let index = Int(operand.index)
                guard index < frame.arguments.count else { throw .indexOutOfRange("parameter \(index)") }
                slot = try object.routingSlots().element(at: Int(frame.arguments[index]))
            case 1:
                return try object.placeInSlot(caller, slot: 0, cleanOld: true) ? .gotoTrue : .gotoFalse
            case 2:
                slot = inFront
            case 3:
                slot = try object.routingSlots().element(at: Int(operand.index))
            case 4:
                slot = try frame.vm.globalRoutingSlots().element(at: Int(operand.index))
            default:
                throw .unsupported("Snap mode \(operand.mode)")
            }
            guard let slot else { return .gotoFalse }

            let search = try frame.vm.findSpots(for: slot, around: object, for: caller)
            let snapsFacing = slot.flags.contains(.snapToDirection)
            if slot.snapTargetSlot >= 0 {
                guard try object.placeInSlot(caller, slot: Int(slot.snapTargetSlot), cleanOld: true) else { return .gotoFalse }
                if snapsFacing, let facing = search.spots.first?.facing { caller.direction = Direction(radians: facing) }
                return .gotoTrue
            }
            guard let spot = search.spots.first else {
                if search.failure == .noValidGoals { try caller.setValue(2, of: ObjectVariable.primitiveResult.rawValue) }
                try caller.setValue(search.blocker?.objectID ?? 0, of: ObjectVariable.primitiveResultID.rawValue)
                if operand.flags & 2 != 0, let blocker = search.blocker { try frame.vm.shoo(blocker, by: caller) }
                return .gotoFalse
            }
            let facing = snapsFacing ? spot.facing.map(Direction.init(radians:)) ?? caller.direction : caller.direction
            let placed = try frame.vm.place(caller.group, at: spot.position, facing: facing)
            guard placed.status == .success else {
                if placed.status == .locationOutOfBounds { try caller.setValue(2, of: ObjectVariable.primitiveResult.rawValue) }
                try caller.setValue(placed.object?.objectID ?? 0, of: ObjectVariable.primitiveResultID.rawValue)
                if operand.flags & 2 != 0, let blocker = placed.object { try frame.vm.shoo(blocker, by: caller) }
                return .gotoFalse
            }
            return .gotoTrue
        }
    }
}

extension Array {
    /// The element at an index, or `nil` past either end.
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Direction {
    /// The compass facing nearest an angle in radians clockwise from north.
    init(radians: Double) {
        let notches = (radians / DeterministicMath.quarterPi).rounded()
        self.init(notch: notches.isFinite ? Int(max(min(notches, 1_000), -1_000)) : 0)
    }
}
