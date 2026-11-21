import TSOFiles

extension Primitives {
    /// Renames the running interaction (opcode 50).
    ///
    /// The name is the string the operand numbers from 1 in a string table of the code owner's
    /// file, the only scope 1.1097.1.0's 355 instructions use; other scopes are unsupported. A
    /// missing table or string, or string 0, leaves the name. In a check tree it changes nothing,
    /// since Simburbia builds no pie menus. It goes true.
    ///
    /// The name is kept as the table writes it: tokens such as a Sim's name, which TSO fills in
    /// for display, aren't filled in.
    ///
    /// With no interaction running, it fails, with an error for the routine.
    public enum ChangeActionString: Primitive {
        public static let name = "change_action_string"
        public static let opcode: UInt8 = 50

        public struct Operand: PrimitiveOperand, Equatable {
            public var stringTable: UInt16
            /// 0 for the code owner's file.
            public var scope: UInt16
            /// The string's number, from 1.
            public var stringID: UInt8

            public init(stringTable: UInt16, scope: UInt16 = 0, stringID: UInt8) {
                self.stringTable = stringTable
                self.scope = scope
                self.stringID = stringID
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                stringTable = reader.uint16()
                scope = reader.uint16()
                stringID = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(stringTable)
                    writer.uint16(scope)
                    writer.uint8(stringID)
                }
            }
        }

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard operand.scope == 0 else { throw .unsupported("Change Action String scope \(operand.scope)") }
            let table: STR?
            do {
                table = try frame.codeOwner.resource.chunk(STR.self, id: operand.stringTable)
            } catch {
                throw .simantics("STR# \(operand.stringTable) doesn't parse: \(error)")
            }
            guard let table, operand.stringID > 0, let name = table.table.string(at: Int(operand.stringID) - 1) else {
                return .gotoTrue
            }
            let thread = frame.thread
            if thread.isCheck { return .gotoTrue }
            guard !thread.queue.isEmpty else { throw .simantics("Change Action String with no interaction running") }
            thread.queue[0].name = name
            return .gotoTrue
        }
    }
}
