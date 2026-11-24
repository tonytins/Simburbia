import TSOFiles

extension Primitives {
    /// A routing slot by scope: 0, the stack object's slot numbered by the parameter `data` names;
    /// 1, its slot numbered `data`; 2, the global's slot numbered `data`. `nil` past the slots.
    static func routingSlot(scope: Int, data: Int, object: Entity, in frame: StackFrame) throws(SimAnticsError) -> SLOT.Slot? {
        switch scope {
        case 0:
            guard data < frame.arguments.count else { throw .indexOutOfRange("parameter \(data)") }
            return try object.routingSlots().element(at: Int(frame.arguments[data]))
        case 1:
            return try object.routingSlots().element(at: data)
        case 2:
            return try frame.vm.globalRoutingSlots().element(at: data)
        default:
            return nil
        }
    }

    /// Pushes a route to a slot's spots around `object` for the caller (``RoutingFrame``), or one
    /// that fails at once with the slot's reason when it has none. It carries on into the route.
    static func route(to slot: SLOT.Slot, around object: Entity, callsFailureTree: Bool, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
        guard let sim = frame.caller, sim.isAvatar else { throw .invalidCast("only a Sim routes") }
        let search = try frame.vm.findSpots(for: slot, around: object, for: sim)
        let route = search.spots.isEmpty
            ? RoutingFrame(failing: search.failure ?? .noValidGoals, blocker: search.blocker, callsFailureTree: callsFailureTree)
            : RoutingFrame(goals: search.spots.map(RouteGoal.init), callsFailureTree: callsFailureTree)
        frame.thread.pushRoute(route, from: frame)
        return .continue
    }

    /// Walks the calling Sim to one of the stack object's routing slots (opcode 45).
    ///
    /// The slot's scope and number come from the operand (``routingSlot(scope:data:object:in:)``);
    /// it must be a routing slot (type 3). The Sim routes to its best spot it can reach
    /// (``RoutingFrame``) and the routine carries on with true when it arrives, false when the route
    /// fails. Flag 1 skips the route failure feedback. In a check tree, with no stack object, or
    /// with no such slot, it's false. 1,064 instructions on 1.1097.1.0.
    public enum GotoRoutingSlot: Primitive {
        public static let name = "goto_routing_slot"
        public static let opcode: UInt8 = 45

        public struct Operand: PrimitiveOperand, Equatable {
            public var data: UInt16
            /// 0 a parameter, 1 a number, 2 the global's.
            public var scope: UInt16
            /// 1: no failure feedback.
            public var flags: UInt8

            public init(data: UInt16, scope: UInt16, flags: UInt8 = 0) {
                self.data = data
                self.scope = scope
                self.flags = flags
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                data = reader.uint16()
                scope = reader.uint16()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(data)
                    writer.uint16(scope)
                    writer.uint8(flags)
                }
            }
        }

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard !frame.thread.isCheck, let object = frame.stackObject else { return .gotoFalse }
            guard let slot = try routingSlot(scope: Int(operand.scope), data: Int(operand.data), object: object, in: frame),
                  slot.type == 3 else { return .gotoFalse }
            return try route(to: slot, around: object, callsFailureTree: operand.flags & 1 == 0, in: frame)
        }
    }

    /// Walks the calling Sim to a place beside the stack object (opcode 27).
    ///
    /// The place is a routing slot made from the operand. Location -2 is on top of the object;
    /// -1 anywhere near, one to two tiles out in any direction, one tile best; 0 to 7 a side, in
    /// front first and clockwise, one tile to a tile and a half out. Direction -1 lets the Sim face
    /// any way, -2 faces the object, and 0 to 7 is a facing turned with the object. The Sim routes
    /// there as Go To Routing Slot does. Flag 2 skips the route failure feedback; flag 1, allowing a
    /// different level, waits for stairs (phase E5). In a check tree, with no stack object, or one
    /// out of the world, it's false. 711 instructions on 1.1097.1.0.
    public enum GotoRelativePosition: Primitive {
        public static let name = "goto_relative"
        public static let opcode: UInt8 = 27

        public struct Operand: PrimitiveOperand, Equatable {
            public var oldTrapCount: UInt16
            /// -2 on top of, -1 anywhere near, 0 to 7 a side.
            public var location: Int8
            /// -2 facing the object, -1 any way, 0 to 7 a facing turned with the object.
            public var direction: Int8
            public var routeCount: UInt16
            /// 1 allows a different level, 2 skips the failure feedback.
            public var flags: UInt8

            public init(oldTrapCount: UInt16 = 0, location: Int8, direction: Int8, routeCount: UInt16 = 0, flags: UInt8 = 0) {
                self.oldTrapCount = oldTrapCount
                self.location = location
                self.direction = direction
                self.routeCount = routeCount
                self.flags = flags
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                oldTrapCount = reader.uint16()
                location = Int8(bitPattern: reader.uint8())
                direction = Int8(bitPattern: reader.uint8())
                routeCount = reader.uint16()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(oldTrapCount)
                    writer.uint8(UInt8(bitPattern: location))
                    writer.uint8(UInt8(bitPattern: direction))
                    writer.uint16(routeCount)
                    writer.uint8(flags)
                }
            }
        }

        /// The slot the operand describes.
        static func slot(for operand: Operand) -> SLOT.Slot {
            var slot = SLOT.Slot(type: 3)
            switch operand.location {
            case -2:
                break
            case -1:
                slot.minProximity = 16
                slot.maxProximity = 32
                slot.optimalProximity = 16
                slot.flags = SLOT.Flags(rawValue: 255)
            default:
                slot.minProximity = 16
                slot.maxProximity = 24
                slot.flags = SLOT.Flags(rawValue: Int32(1) << Int32(Int(operand.location) & 7))
            }
            slot.facing = operand.direction == -1 ? SLOT.Facing.anywhere : Int32(operand.direction)
            return slot
        }

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard !frame.thread.isCheck, let object = frame.stackObject, !object.position.isOutOfWorld else { return .gotoFalse }
            return try route(to: slot(for: operand), around: object, callsFailureTree: operand.flags & 2 == 0, in: frame)
        }
    }
}
