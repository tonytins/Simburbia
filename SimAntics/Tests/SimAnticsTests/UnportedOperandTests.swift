import Testing
@testable import SimAntics

/// The operands of primitives this port decodes without running, checked against their layouts.
@Suite struct UnportedOperandTests {
    @Test func everyOperandEncodesBackToTheBytesFreeSOWrites() {
        // The bytes an operand writes: unread and padding bytes are zero.
        let samples: [UInt8: [UInt8]] = [
            1: [7, 0, 0, 0, 0, 0, 0, 0], 9: [2, 1, 0, 0, 0, 0, 0, 0],
            24: [1, 2, 3, 4, 5, 0, 0, 0], 26: [1, 2, 3, 4, 8, 0, 0xFF, 0xFF],
            36: [1, 2, 3, 4, 5, 6, 7, 8],
            40: [4, 0, 0, 0, 0, 0, 0, 0], 43: [1, 0, 2, 0, 3, 0, 4, 0],
            62: [1, 2, 3, 1, 0x78, 0x56, 0x34, 0x12], 67: [0xEF, 0xBE, 0xAD, 0xDE, 4, 0, 0, 0],
        ]
        for (opcode, bytes) in samples {
            let operand = PrimitiveTable.unportedOperand(opcode: UInt16(opcode), bytes: bytes)
            #expect(operand?.encoded() == bytes, "opcode \(opcode)")
        }
        for opcode: UInt16 in [30, 65] {
            #expect(PrimitiveTable.unportedOperand(opcode: opcode, bytes: [1, 2, 3])?.encoded() == [UInt8](repeating: 0, count: 8))
        }
    }

    @Test func fieldsReadAsFreeSOReadsThem() throws {

        let old = try #require(PrimitiveTable.unportedOperand(opcode: 24, bytes: [1, 2, 3, 4, 5]) as? Primitives.OldRelationship.Operand)
        #expect(old.variable == Variable(.parameters, 3) && old.fsoCompatFields.first?.name == "SetMode")
    }

    @Test func shortOperandsReadAsZeroAndUnknownOpcodesDecodeToNothing() {
        #expect(PrimitiveTable.unportedOperand(opcode: 43, bytes: [])?.encoded() == [UInt8](repeating: 0, count: 8))
        #expect(PrimitiveTable.unportedOperand(opcode: 2, bytes: [1, 2]) == nil)     // expression: ported
        #expect(PrimitiveTable.unportedOperand(opcode: 51, bytes: [1, 2]) == nil)    // FreeSO registers none
        #expect(PrimitiveTable.unportedOperand(opcode: 300, bytes: [1, 2]) == nil)   // a call
    }

    @Test func noOperandIsBothPortedAndUnported() {
        for opcode in PrimitiveTable.unportedOperands.keys {
            #expect(PrimitiveTable.standard.name(of: opcode) == nil, "opcode \(opcode)")
        }
    }
}
