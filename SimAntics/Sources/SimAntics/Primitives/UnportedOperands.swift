// The operands of primitives this port doesn't run yet, decoded, so tools can show what an
// instruction asks for. When its primitive is ported, the operand moves into that
// primitive's own file.

/// An operand that lists its values under the field names tools know them by. Booleans are 0 or 1;
/// scopes and enums are their raw values.
public protocol FSOCompatOperand: PrimitiveOperand {
    var fsoCompatFields: [(name: String, value: Int64)] { get }
}

extension PrimitiveTable {
    /// Operand types for TSO primitives Simburbia doesn't run yet, by opcode. Primitives with no
    /// operand (syslog, find best action) decode to
    /// ``Primitives/EmptyOperand``.
    public static let unportedOperands: [UInt8: any FSOCompatOperand.Type] = [
        1: Primitives.GenericTSOCall.Operand.self,
        9: Primitives.Burn.Operand.self,
        14: Primitives.FindBestObjectForFunction.Operand.self,
        20: Primitives.RunFunctionalTree.Operand.self,
        22: Primitives.LookTowards.Operand.self,
        24: Primitives.OldRelationship.Operand.self,
        26: Primitives.Relationship.Operand.self,
        27: Primitives.GotoRelativePosition.Operand.self,
        30: Primitives.EmptyOperand.self,
        36: Primitives.Dialog.Operand.self,
        38: Primitives.Dialog.Operand.self,
        39: Primitives.Dialog.Operand.self,
        40: Primitives.OnlineJobsCall.Operand.self,
        43: Primitives.DropOnto.Operand.self,
        45: Primitives.GotoRoutingSlot.Operand.self,
        46: Primitives.Snap.Operand.self,
        62: Primitives.InvokePlugin.Operand.self,
        65: Primitives.EmptyOperand.self,
        67: Primitives.InventoryOperations.Operand.self,
    ]

    /// An unported primitive's operand, decoded, or `nil` if this port doesn't know its layout.
    public static func unportedOperand(opcode: UInt16, bytes: [UInt8]) -> (any FSOCompatOperand)? {
        guard opcode < 256, let type = unportedOperands[UInt8(opcode)] else { return nil }
        return type.init(bytes: bytes)
    }
}

extension Primitives {
    /// The operand of a primitive that reads none.
    public struct EmptyOperand: FSOCompatOperand, Equatable {
        public init() {}
        public init(bytes: [UInt8]) {}
        public func encoded() -> [UInt8] { OperandWriter.bytes { _ in } }
        public var fsoCompatFields: [(name: String, value: Int64)] { [] }
    }

    /// Dialog (opcodes 36, 38, and 39: private, global, and semi-global strings). The IDs
    /// index the strings of the dialog's string table.
    public enum Dialog {
        public struct Operand: FSOCompatOperand, Equatable {
            public var cancelStringID: UInt8
            public var iconNameStringID: UInt8
            public var messageStringID: UInt8
            public var yesStringID: UInt8
            public var noStringID: UInt8
            /// The kind of dialog.
            public var type: UInt8
            public var titleStringID: UInt8
            public var flags: UInt8

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                cancelStringID = reader.uint8()
                iconNameStringID = reader.uint8()
                messageStringID = reader.uint8()
                yesStringID = reader.uint8()
                noStringID = reader.uint8()
                type = reader.uint8()
                titleStringID = reader.uint8()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                [cancelStringID, iconNameStringID, messageStringID, yesStringID, noStringID, type, titleStringID, flags]
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("CancelStringID", Int64(cancelStringID)), ("IconNameStringID", Int64(iconNameStringID)),
                 ("MessageStringID", Int64(messageStringID)), ("YesStringID", Int64(yesStringID)),
                 ("NoStringID", Int64(noStringID)), ("Type", Int64(type)), ("TitleStringID", Int64(titleStringID)),
                 ("Flags", Int64(flags))]
            }
        }
    }

    /// Go to Routing Slot (opcode 45).
    public enum GotoRoutingSlot {
        public struct Operand: FSOCompatOperand, Equatable {
            public var data: UInt16
            /// How ``data`` picks the slot.
            public var type: UInt16
            public var flags: UInt8

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                data = reader.uint16()
                type = reader.uint16()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(data)
                    writer.uint16(type)
                    writer.uint8(flags)
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("Data", Int64(data)), ("Type", Int64(type)), ("Flags", Int64(flags))]
            }
        }
    }

    /// Relationship (opcode 26). Its scope and data are a ``Variable`` here.
    public enum Relationship {
        public struct Operand: FSOCompatOperand, VariableOperand, Equatable {
            public var relationshipVariable: UInt8
            public var mode: UInt8
            public var flags: UInt8
            public var local: UInt8
            public var variable: Variable

            public var variables: [Variable] { [variable] }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                relationshipVariable = reader.uint8()
                mode = reader.uint8()
                flags = reader.uint8()
                local = reader.uint8()
                let scope = reader.uint16()
                variable = Variable(rawScope: scope, data: reader.int16())
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    for byte in [relationshipVariable, mode, flags, local] { writer.uint8(byte) }
                    writer.uint16(variable.rawScope)
                    writer.int16(variable.data)
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("RelVar", Int64(relationshipVariable)), ("Mode", Int64(mode)), ("Flags", Int64(flags)),
                 ("Local", Int64(local)), ("VarScope", Int64(variable.rawScope)), ("VarData", Int64(variable.data))]
            }
        }
    }

    /// Old Relationship (opcode 24): the same primitive as ``Relationship`` with an older
    /// operand. Its variable is always a parameter.
    public enum OldRelationship {
        public struct Operand: FSOCompatOperand, VariableOperand, Equatable {
            /// Whether it gets or sets.
            public var setMode: UInt8
            public var relationshipVariable: UInt8
            /// The parameter that holds the value.
            public var variable: Variable
            public var mode: UInt8
            public var flags: UInt8

            public var variables: [Variable] { [variable] }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                setMode = reader.uint8()
                relationshipVariable = reader.uint8()
                variable = Variable(.parameters, Int16(reader.uint8()))
                mode = reader.uint8()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint8(setMode)
                    writer.uint8(relationshipVariable)
                    writer.uint8(UInt8(truncatingIfNeeded: variable.data))
                    writer.uint8(mode)
                    writer.uint8(flags)
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("SetMode", Int64(setMode)), ("RelVar", Int64(relationshipVariable)), ("VarScope", Int64(variable.rawScope)),
                 ("VarData", Int64(variable.data)), ("Mode", Int64(mode)), ("Flags", Int64(flags))]
            }
        }
    }

    /// Go to Relative Position (opcode 27). Location and direction are signed bytes.
    public enum GotoRelativePosition {
        public struct Operand: FSOCompatOperand, Equatable {
            public var oldTrapCount: UInt16
            /// Where to go relative to the object.
            public var location: Int8
            /// Which way to face.
            public var direction: Int8
            public var routeCount: UInt16
            public var flags: UInt8

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

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("OldTrapCount", Int64(oldTrapCount)), ("Location", Int64(location)), ("Direction", Int64(direction)),
                 ("RouteCount", Int64(routeCount)), ("Flags", Int64(flags))]
            }
        }
    }

    /// Snap (opcode 46).
    public enum Snap {
        public struct Operand: FSOCompatOperand, Equatable {
            public var index: UInt16
            /// How ``index`` picks the slot.
            public var mode: UInt16
            public var flags: UInt8

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

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("Index", Int64(index)), ("Mode", Int64(mode)), ("Flags", Int64(flags))]
            }
        }
    }

    /// One-byte calls: Generic Sims Online Call (opcode 1), Look Towards (22), and Online Jobs
    /// Call (40).
    public enum GenericTSOCall {
        public struct Operand: FSOCompatOperand, Equatable {
            /// The call.
            public var call: UInt8
            public init(bytes: [UInt8]) { call = bytes.first ?? 0 }
            public func encoded() -> [UInt8] { OperandWriter.bytes { $0.uint8(call) } }
            public var fsoCompatFields: [(name: String, value: Int64)] { [("Call", Int64(call))] }
        }
    }

    public enum LookTowards {
        public struct Operand: FSOCompatOperand, Equatable {
            /// What to look at.
            public var mode: UInt8
            public init(bytes: [UInt8]) { mode = bytes.first ?? 0 }
            public func encoded() -> [UInt8] { OperandWriter.bytes { $0.uint8(mode) } }
            public var fsoCompatFields: [(name: String, value: Int64)] { [("Mode", Int64(mode))] }
        }
    }

    public enum OnlineJobsCall {
        public struct Operand: FSOCompatOperand, Equatable {
            /// The call.
            public var call: UInt8
            public init(bytes: [UInt8]) { call = bytes.first ?? 0 }
            public func encoded() -> [UInt8] { OperandWriter.bytes { $0.uint8(call) } }
            public var fsoCompatFields: [(name: String, value: Int64)] { [("Call", Int64(call))] }
        }
    }

    /// Drop Onto (opcode 43).
    public enum DropOnto {
        public struct Operand: FSOCompatOperand, Equatable {
            public var sourceSlotMode: UInt16
            public var sourceSlotNumber: UInt16
            public var destinationSlotMode: UInt16
            public var destinationSlotNumber: UInt16

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                sourceSlotMode = reader.uint16()
                sourceSlotNumber = reader.uint16()
                destinationSlotMode = reader.uint16()
                destinationSlotNumber = reader.uint16()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    for value in [sourceSlotMode, sourceSlotNumber, destinationSlotMode, destinationSlotNumber] { writer.uint16(value) }
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("SrcSlotMode", Int64(sourceSlotMode)), ("SrcSlotNum", Int64(sourceSlotNumber)),
                 ("DestSlotMode", Int64(destinationSlotMode)), ("DestSlotNum", Int64(destinationSlotNumber))]
            }
        }
    }

    /// Run Functional Tree (opcode 20) and Find Best Object for Function (14, which reads
    /// only the function).
    public enum RunFunctionalTree {
        public struct Operand: FSOCompatOperand, Equatable {
            public var function: UInt16
            public var flags: UInt8

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                function = reader.uint16()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(function)
                    writer.uint8(flags)
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("Function", Int64(function)), ("Flags", Int64(flags))]
            }
        }
    }

    public enum FindBestObjectForFunction {
        public struct Operand: FSOCompatOperand, Equatable {
            public var function: UInt16
            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                function = reader.uint16()
            }
            public func encoded() -> [UInt8] { OperandWriter.bytes { $0.uint16(function) } }
            public var fsoCompatFields: [(name: String, value: Int64)] { [("Function", Int64(function))] }
        }
    }

    /// Burn (opcode 9).
    public enum Burn {
        public struct Operand: FSOCompatOperand, Equatable {
            /// What burns.
            public var type: UInt8
            public var burnsBusyObjects: Bool

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                type = reader.uint8()
                burnsBusyObjects = reader.uint8() > 0
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint8(type)
                    writer.uint8(burnsBusyObjects ? 1 : 0)
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("Type", Int64(type)), ("BurnBusyObjects", burnsBusyObjects ? 1 : 0)]
            }
        }
    }

    /// Invoke Plugin (opcode 62).
    public enum InvokePlugin {
        public struct Operand: FSOCompatOperand, Equatable {
            public var personLocal: UInt8
            public var objectLocal: UInt8
            public var eventLocal: UInt8
            public var isJoinable: Bool
            public var pluginID: UInt32

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                personLocal = reader.uint8()
                objectLocal = reader.uint8()
                eventLocal = reader.uint8()
                isJoinable = reader.uint8() > 0
                pluginID = reader.uint32()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    for byte in [personLocal, objectLocal, eventLocal, isJoinable ? 1 : 0] { writer.uint8(byte) }
                    writer.uint32(pluginID)
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("PersonLocal", Int64(personLocal)), ("ObjectLocal", Int64(objectLocal)), ("EventLocal", Int64(eventLocal)),
                 ("Joinable", isJoinable ? 1 : 0), ("PluginID", Int64(pluginID))]
            }
        }
    }

    /// Inventory Operations (opcode 67).
    public enum InventoryOperations {
        public struct Operand: FSOCompatOperand, Equatable {
            public var guid: UInt32
            /// The operation.
            public var mode: UInt8

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                guid = reader.uint32()
                mode = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint32(guid)
                    writer.uint8(mode)
                }
            }

            public var fsoCompatFields: [(name: String, value: Int64)] {
                [("GUID", Int64(guid)), ("Mode", Int64(mode))]
            }
        }
    }
}
