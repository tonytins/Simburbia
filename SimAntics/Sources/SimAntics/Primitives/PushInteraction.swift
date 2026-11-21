extension Primitives {
    /// Queues one of an object's interactions on the stack object (opcode 13).
    ///
    /// TSO's Sims don't choose their own actions; their code and objects' code push them with
    /// this. The object whose interaction it is has its ID in the argument the operand names, or the
    /// local with flag 2. Its interaction with the operand's number becomes an action that must run
    /// (its check tree isn't run), on the object, at the operand's priority, and goes into the stack
    /// object's queue (``VMThread/enqueue(_:)``). It's true when queued, and false when the object
    /// has no such interaction or its action tree doesn't exist.
    ///
    /// The priorities: 0 the running interaction's (in an interaction's routine; else 1), at least
    /// 1; then maximum, autonomous, user-driven, and the parent-idle, parent-exit, and idle modes
    /// at their priorities. Others queue at 0. The flags, from the SimAntics Wiki and 1.1097.1.0's
    /// 520 instructions:
    ///
    /// - 1 (366): the icon comes from the object in the local `iconLocation` names. Only drawing
    ///   would show it; Simburbia keeps no icon.
    /// - 2 (460): the object's ID is in a local.
    /// - 4 (107): continue as the current interaction: it leapfrogs the waiting ones.
    /// - 8 (121): carry the running interaction's name over to the new one.
    /// - 16 (6): unknown, ignored.
    ///
    /// No stack object, an object ID past the locals or arguments, or an ID with no object, fails,
    /// with an error for the routine.
    public enum PushInteraction: Primitive {
        public static let name = "push_interaction"
        public static let opcode: UInt8 = 13

        public struct Operand: PrimitiveOperand, Equatable {
            /// The interaction's number in the object's table.
            public var interaction: UInt8
            /// The local or argument that holds the object's ID.
            public var objectLocation: UInt8
            public var priority: UInt8
            public var flags: UInt8
            /// The local holding the icon's object, with flag 1.
            public var iconLocation: UInt8

            public init(interaction: UInt8, objectLocation: UInt8, priority: UInt8, flags: UInt8 = 0, iconLocation: UInt8 = 0) {
                self.interaction = interaction
                self.objectLocation = objectLocation
                self.priority = priority
                self.flags = flags
                self.iconLocation = iconLocation
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                interaction = reader.uint8()
                objectLocation = reader.uint8()
                priority = reader.uint8()
                flags = reader.uint8()
                iconLocation = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    for byte in [interaction, objectLocation, priority, flags, iconLocation] { writer.uint8(byte) }
                }
            }

            public var objectInLocal: Bool { flags & 2 != 0 }
            public var continuesCurrent: Bool { flags & 4 != 0 }
            public var carriesNameOver: Bool { flags & 8 != 0 }
        }

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let target = frame.stackObject else { throw .nullReference("Push Interaction has no stack object") }
            let index = Int(operand.objectLocation)
            let id: Int16
            if operand.objectInLocal {
                guard index < frame.locals.count else { throw .indexOutOfRange("local \(index)") }
                id = frame.locals[index]
            } else {
                guard index < frame.arguments.count else { throw .indexOutOfRange("parameter \(index)") }
                id = frame.arguments[index]
            }
            guard let source = frame.vm.entity(id: id) else { throw .nullReference("Push Interaction: no object \(id)") }

            let running = frame.isActionTree ? frame.thread.queue.first : nil
            var priority: Int16 = 0
            var mode = QueuedAction.Mode.normal
            switch operand.priority {
            case 0: priority = max(1, running?.priority ?? 1)
            case 1: priority = QueuedAction.Priority.maximum
            case 2: priority = QueuedAction.Priority.autonomous
            case 3: priority = QueuedAction.Priority.userDriven
            case 4: (priority, mode) = (QueuedAction.Priority.parentIdle, .parentIdle)
            case 5: (priority, mode) = (QueuedAction.Priority.parentExit, .parentExit)
            case 6: (priority, mode) = (QueuedAction.Priority.idle, .idle)
            default: break
            }

            let interactions = try frame.vm.interactions(of: source.object)
            guard let interaction = interactions.first(where: { $0.number == UInt32(operand.interaction) }),
                  var action = try QueuedAction(interaction, of: source) else { return .gotoFalse }
            action.priority = priority
            action.mode = mode
            action.flags.insert(.mustRun)
            if operand.continuesCurrent { action.flags.insert(.leapfrog) }
            if operand.carriesNameOver, let running { action.name = running.name }
            target.thread.enqueue(action)
            return .gotoTrue
        }
    }
}
