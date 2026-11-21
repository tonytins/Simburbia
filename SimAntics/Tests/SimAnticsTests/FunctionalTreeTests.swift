import Testing
@testable import SimAntics

/// The chair's OBJD words for its sit (8) and clean (11) routines; its definition has no function
/// table, so neither has a condition.
private let sitWord = 30, cleanWord = 57

private func tile(_ x: Int16, _ y: Int16) -> LotPosition { .center(ofTileX: x, y: y, level: 1) }

/// Sitting adds 1 to attribute 0 and returns true; cleaning adds 1 to attribute 1.
private let functionRoutines = [
    bhavChunk(id: 4100, [addToAttribute(0, 1)]),
    bhavChunk(id: 4101, arguments: 2, [addToAttribute(1, 1)]),
]

@Suite struct FunctionalTreeTests {
    @Test func operandsEncodeBackToTheirBytes() {
        #expect(Primitives.RunFunctionalTree.Operand(bytes: [0x34, 0x12, 9, 0, 0, 0, 0, 0]).encoded() == [0x34, 0x12, 9, 0, 0, 0, 0, 0])
        #expect(Primitives.FindBestObjectForFunction.Operand(bytes: [0x34, 0x12, 0, 0, 0, 0, 0, 0]).encoded() == [0x34, 0x12, 0, 0, 0, 0, 0, 0])
    }

    /// Run Functional Tree pushes the stack object's sit routine as a subroutine, on the stack
    /// object, with its own code and zeroed arguments, as many as it takes.
    @Test func runsTheStackObjectsRoutineForAFunction() throws {
        try withVM(chair: functionRoutines, chairWords: [sitWord: 4100, cleanWord: 4101]) { vm, chair throws in
            let other = try vm.addObject(guid: chairGUID, id: 2)
            let operand = Primitives.RunFunctionalTree.Operand(function: 11).encoded()
            let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 20, operand: operand, caller: other, stackObjectID: chair.objectID)
            #expect(try primitive.execute(in: frame) == .continue)
            let child = try #require(other.thread.stack.last)
            #expect(child.routine.id == 4101 && child.callee === chair && child.stackObject === chair && child.caller === other)
            #expect(child.arguments == [0, 0])
        }
    }

    @Test func withoutTheRoutineOrAStackObjectItsFalse() throws {
        try withVM(chair: functionRoutines, chairWords: [sitWord: 4100]) { vm, chair throws in
            func run(_ function: UInt16, stackObject: Int16) throws -> ExitCode {
                let operand = Primitives.RunFunctionalTree.Operand(function: function).encoded()
                let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 20, operand: operand, caller: chair, stackObjectID: stackObject)
                defer { chair.thread.stack.removeAll() }
                return try primitive.execute(in: frame)
            }
            #expect(try run(11, stackObject: chair.objectID) == .gotoFalse, "no clean routine")
            #expect(try run(8, stackObject: 0) == .gotoFalse, "no stack object")
            #expect(try run(65535, stackObject: chair.objectID) == .gotoFalse)
            #expect(throws: SimAnticsError.indexOutOfRange("object function 15")) { try run(15, stackObject: chair.objectID) }
        }
    }

    /// Find Best Object For Function takes the nearest object with the routine, leaving out what's
    /// out of the world, locked out, or occupied.
    @Test func findsTheNearestUsableObject() throws {
        try withVM(chair: functionRoutines, chairWords: [sitWord: 4100]) { vm, caller throws in
            let near = try vm.addObject(guid: chairGUID, id: 2)
            let far = try vm.addObject(guid: chairGUID, id: 3)
            _ = try vm.addObject(guid: chairGUID, id: 4)   // out of the world
            try vm.move(caller, to: tile(1, 1))
            try vm.move(near, to: tile(2, 1))
            try vm.move(far, to: tile(6, 6))
            func best() throws -> Int16? {
                let operand = Primitives.FindBestObjectForFunction.Operand(function: 8).encoded()
                let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 14, operand: operand, caller: caller)
                defer { caller.thread.stack.removeAll() }
                return try primitive.execute(in: frame) == .gotoTrue ? frame.stackObject?.objectID : nil
            }
            #expect(try best() == caller.objectID, "the caller's own chair is nearest of all")
            caller.setFlag(EntityFlag.occupied, true)
            #expect(try best() == near.objectID)
            try near.setValue(100, of: ObjectVariable.lockoutCount.rawValue)
            #expect(try best() == far.objectID)
            far.disabledFlags = Entity.lotCategoryWrong
            #expect(try best() == nil)
        }
    }

    /// Cleaning scores by dirt, which must be at least 800: the dirtier object wins over the
    /// nearer one, and one below the threshold isn't a candidate.
    @Test func scoresByTheFunctionsObjectData() throws {
        try withVM(chair: functionRoutines, chairWords: [cleanWord: 4101]) { vm, caller throws in
            let near = try vm.addObject(guid: chairGUID, id: 2)
            let far = try vm.addObject(guid: chairGUID, id: 3)
            try vm.move(caller, to: tile(1, 1))
            try vm.move(near, to: tile(2, 1))
            try vm.move(far, to: tile(6, 6))
            try caller.setValue(100, of: ObjectVariable.dirtyLevel.rawValue)
            try near.setValue(850, of: ObjectVariable.dirtyLevel.rawValue)
            try far.setValue(1000, of: ObjectVariable.dirtyLevel.rawValue)
            let operand = Primitives.FindBestObjectForFunction.Operand(function: 11).encoded()
            let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 14, operand: operand, caller: caller)
            #expect(try primitive.execute(in: frame) == .gotoTrue && frame.stackObject === far)
        }
    }
}
