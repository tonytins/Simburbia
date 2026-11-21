import Foundation
import Testing
import TSOContent
import TSOFiles
@testable import SimAntics

private let trayGUID: UInt32 = 0x401

private func strChunk(id: UInt16, _ strings: [String]) -> ChunkFixture {
    var writer = ByteWriter()
    writer.int16(-1)
    writer.uint16(UInt16(strings.count))
    for string in strings { writer.raw(Array(string.utf8) + [0]) }
    return ChunkFixture(type: "STR#", id: id, contents: writer.bytes)
}

/// A version 8 `SLOT` chunk of container slots with these heights and offsets' z.
private func slotChunk(id: UInt16, _ slots: [(height: Int32, z: Float)]) -> ChunkFixture {
    var writer = ByteWriter()
    writer.uint32(0); writer.uint32(8); writer.ascii("TOLS"); writer.uint32(UInt32(slots.count))
    for slot in slots {
        writer.uint16(0)
        for value: Float in [0, 0, slot.z] { writer.uint32(value.bitPattern) }
        for value: Int32 in [0, 0, 0, 0, -1, 0, 0, 0, 0, 0] { writer.int32(value) }   // through the proximities and two unknown words
        writer.uint32(Float(0).bitPattern)
        writer.int32(slot.height)
    }
    return ChunkFixture(type: "SLOT", id: id, contents: writer.bytes)
}

/// The reach and carry animations, 10 and 5 frames: event 0 at 100 ms (frame 3), then 7 at 200.
private let animations = animationsArchive(
    ["a2o-reach-floorht", "a2o-reach-seatht", "a2o-reach-tableht", "a2o-sit-reach-table"].map { ($0, 10, [(100, 0), (200, 7)]) }
        + [("a2o-rarm-carry-loop", 5, [])])

/// A female Sim standing on tile 3,3 facing north; a tray with three container slots (a low
/// table's, a table's, and a non-standard one 1.4 up); and a lamp, all on an 8 by 8 lot. The
/// Sim's object has suits in `STR#` 304, and the global one.
private func withHands(_ body: (VM, Entity, Entity, Entity) throws -> Void) throws {
    let bodyStrings = ["adult", "", "", "", "", "", "", "", "", "", "", "Pat", "female", "27", "med"]
    try withVM(chair: [strChunk(id: 200, bodyStrings), strChunk(id: 304, ["apron", "0x1A0000000D", "not an outfit"]),
                       objdChunk(label: "tray", guid: trayGUID, words: [18: 128], id: 140),
                       objdChunk(label: "lamp", guid: lampGUID, id: 133),
                       slotChunk(id: 128, [(2, 0), (3, 0), (5, 1.4)])],
               chairWords: [7: 2, 17: 200], global: [strChunk(id: 150, ["walk0", "walk1"]), strChunk(id: 304, ["hat"])],
               objects: [trayGUID, lampGUID], files: [animations]) { vm, _ throws in
        vm.architecture = try Architecture(width: 8, height: 8)
        let sim = try #require(try vm.createObject(guid: chairGUID)?.objects.first)
        let tray = try #require(try vm.createObject(guid: trayGUID)?.objects.first)
        let lamp = try #require(try vm.createObject(guid: lampGUID)?.objects.first)
        for entity in [sim, tray, lamp] {
            entity.objectData[Int(ObjectVariable.placementFlags.rawValue)] = PlacementFlags.onTerrain.rawValue
            entity.objectData[Int(ObjectVariable.allowedHeightFlags.rawValue)] = 1
        }
        #expect(try vm.place(sim.group, at: .center(ofTileX: 3, y: 3, level: 1), facing: .north).status == .success)
        try body(vm, sim, tray, lamp)
    }
}

/// Runs a primitive once a tick, the Sim's animations advancing after it, until it isn't waiting.
private func runToTheEnd(_ opcode: UInt8, _ operand: [UInt8], on sim: Entity, stackObject: Entity, in vm: VM,
                         arguments: [Int16] = [0, 0, 0, 0]) throws -> (ExitCode, [String]) {
    var started: [String] = []
    for _ in 0..<100 {
        let (primitive, frame) = try vm.makePrimitiveFrame(opcode: opcode, operand: operand, caller: sim,
                                                           arguments: arguments, stackObjectID: stackObject.objectID)
        let code = try primitive.execute(in: frame)
        sim.thread.stack.removeAll()
        if let key = sim.sim.animations.first?.clip.key, started.last != key { started.append(key) }
        guard code == .continueNextTick else { return (code, started) }
        sim.advanceAnimations()
    }
    return (.error, started)
}

@Suite struct GrabAndDropTests {
    /// Grab takes the stack object in hand and starts the carry animation; a full hand can't.
    @Test func grabsTheStackObject() throws {
        try withHands { vm, sim, tray, lamp throws in
            let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 4, operand: [], caller: sim, stackObjectID: lamp.objectID)
            #expect(try primitive.execute(in: frame) == .gotoTrue)
            #expect(sim.slot(0) === lamp && lamp.container === sim && sim.sim.carryAnimation?.clip.key == "a2o-rarm-carry-loop")
            frame.stackObjectID = tray.objectID
            #expect(try primitive.execute(in: frame) == .gotoFalse)
            sim.thread.stack.removeAll()
            #expect(throws: SimAnticsError.self) { try vm.runPrimitive(opcode: 4, operand: [], caller: sim) }
        }
    }

    /// Drop puts it on the tile the Sim faces, and empties the hand and the carry animation.
    @Test func dropsOnTheTileInFront() throws {
        try withHands { vm, sim, _, lamp throws in
            #expect(try vm.runPrimitive(opcode: 5, operand: [], caller: sim).0 == .gotoFalse)    // nothing held
            try sim.placeInSlot(lamp, slot: 0, cleanOld: true)
            #expect(try vm.runPrimitive(opcode: 5, operand: [], caller: sim).0 == .gotoTrue)
            #expect(sim.slot(0) == nil && lamp.container == nil && sim.sim.carryAnimation == nil)
            #expect(lamp.position == .center(ofTileX: 3, y: 2, level: 1))
        }
    }

    /// With the tile in front taken, the next try is the one north and to its left.
    @Test func triesTheTilesAroundInTurn() throws {
        try withHands { vm, sim, tray, lamp throws in
            #expect(try vm.place(tray.group, at: .center(ofTileX: 3, y: 2, level: 1), facing: .north).status == .success)
            try sim.placeInSlot(lamp, slot: 0, cleanOld: true)
            #expect(try vm.runPrimitive(opcode: 5, operand: [], caller: sim).0 == .gotoTrue)
            #expect(lamp.position == .center(ofTileX: 2, y: 2, level: 1))
        }
    }
}

@Suite struct ReachTests {
    private func reach(_ mode: UInt16, slotParameter: UInt16 = 0) -> [UInt8] {
        Primitives.Reach.Operand(mode: mode, slotParameter: slotParameter).encoded()
    }

    /// Mode 0 reaches for an object on the floor, picks it up on event 0, and goes true at the end.
    @Test func picksUpFromTheFloor() throws {
        try withHands { vm, sim, _, lamp throws in
            #expect(try vm.place(lamp.group, at: .center(ofTileX: 4, y: 3, level: 1), facing: .north).status == .success)
            let (code, started) = try runToTheEnd(47, reach(0), on: sim, stackObject: lamp, in: vm)
            #expect(code == .gotoTrue && started == ["a2o-reach-floorht"])
            #expect(sim.slot(0) === lamp && sim.sim.animations.isEmpty)
        }
    }

    /// The animation follows the slot's height, rounded half to even: a low table's 2.5 is 2.
    @Test func picksTheAnimationByTheSlotsHeight() throws {
        try withHands { vm, sim, tray, lamp throws in
            #expect(try Primitives.Reach.slotHeight(of: tray, slot: 0) == 2)
            #expect(try Primitives.Reach.slotHeight(of: tray, slot: 1) == 4)
            #expect(try Primitives.Reach.slotHeight(of: tray, slot: 2) == 1)
            #expect(throws: SimAnticsError.self) { try Primitives.Reach.slotHeight(of: tray, slot: 3) }
            for (slot, animation) in [(0, "a2o-reach-seatht"), (1, "a2o-reach-tableht"), (2, "a2o-reach-floorht")] {
                try tray.placeInSlot(lamp, slot: slot, cleanOld: true)
                sim.sim.animations = []
                let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 47, operand: reach(0), caller: sim, stackObjectID: lamp.objectID)
                #expect(try primitive.execute(in: frame) == .continueNextTick)
                sim.thread.stack.removeAll()
                #expect(sim.sim.animations.first?.clip.key == animation, "slot \(slot)")
                tray.clearSlot(slot)
            }
        }
    }

    /// Mode 1 takes what's in the numbered slot with an empty hand, and puts what it holds into an
    /// empty one; a slot it doesn't have goes false.
    @Test func takesFromAndPutsIntoASlot() throws {
        try withHands { vm, sim, tray, lamp throws in
            try tray.placeInSlot(lamp, slot: 1, cleanOld: true)
            var (code, _) = try runToTheEnd(47, reach(1, slotParameter: 2), on: sim, stackObject: tray, in: vm, arguments: [0, 0, 1, 0])
            #expect(code == .gotoTrue && sim.slot(0) === lamp && tray.slot(1) == nil)
            (code, _) = try runToTheEnd(47, reach(1, slotParameter: 2), on: sim, stackObject: tray, in: vm, arguments: [0, 0, 2, 0])
            #expect(code == .gotoTrue && sim.slot(0) == nil && tray.slot(2) === lamp)
            (code, _) = try runToTheEnd(47, reach(1, slotParameter: 2), on: sim, stackObject: tray, in: vm, arguments: [0, 0, 9, 0])
            #expect(code == .gotoFalse)
        }
    }

    @Test func refusesWhatItCantDo() throws {
        try withHands { vm, sim, tray, lamp throws in
            #expect(throws: SimAnticsError.self) { try vm.runPrimitive(opcode: 47, operand: reach(0), caller: sim) }   // no stack object
            let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 47, operand: reach(2), caller: sim, stackObjectID: lamp.objectID)
            #expect(throws: SimAnticsError.self) { try primitive.execute(in: frame) }                                  // to the mouth
            sim.thread.stack.removeAll()
            #expect(throws: SimAnticsError.self) { try vm.runPrimitive(opcode: 47, operand: reach(0), caller: tray) }  // not a Sim
        }
    }
}

@Suite struct ChangeSuitTests {
    private func suit(_ data: UInt8, scope: UInt8, flags: UInt16 = 0) -> [UInt8] {
        Primitives.ChangeSuitOrAccessory.Operand(suitData: data, suitScope: scope, flags: flags).encoded()
    }

    /// Object and global suits bind appearances, or with flag 1 unbind one; a missing one skips.
    @Test func bindsAndUnbindsAppearances() throws {
        try withHands { vm, sim, _, _ throws in
            for operand in [suit(0, scope: 2), suit(0, scope: 2), suit(0, scope: 0), suit(9, scope: 2), suit(0, scope: 2, flags: 1)] {
                #expect(try vm.runPrimitive(opcode: 6, operand: operand, caller: sim).0 == .gotoTrue)
            }
            #expect(sim.sim.boundAppearances == ["apron.apr", "hat.apr"])
        }
    }

    /// Person suits change the body and set the current outfit; decorations change nothing here.
    @Test func changesIntoPersonSuits() throws {
        try withHands { vm, sim, _, _ throws in
            _ = try vm.runPrimitive(opcode: 6, operand: suit(1, scope: 1), caller: sim)
            #expect(sim.sim.bodyOutfit == 0x1_0000_000D && sim.personData[PersonData.currentOutfit] == 1)
            _ = try vm.runPrimitive(opcode: 6, operand: suit(5, scope: 1), caller: sim)
            #expect(sim.sim.bodyOutfit == sim.sim.sleepwear && sim.personData[PersonData.currentOutfit] == 5)
            _ = try vm.runPrimitive(opcode: 6, operand: suit(8, scope: 1), caller: sim)
            #expect(sim.personData[PersonData.currentOutfit] == 5)
            // The online job's uniform by grade: a waiter at grade 5 wears the second level.
            sim.personData[PersonData.onlineJobID] = 2
            sim.personData[PersonData.onlineJobGrade] = 5
            _ = try vm.runPrimitive(opcode: 6, operand: suit(3, scope: 1), caller: sim)
            #expect(sim.sim.bodyOutfit == 0x57E_0000_000D)
            sim.personData[PersonData.onlineJobGrade] = 13
            #expect(throws: SimAnticsError.indexOutOfRange("job outfit level 3")) {
                try vm.runPrimitive(opcode: 6, operand: suit(3, scope: 1), caller: sim)
            }
        }
    }

    /// Flag 4 makes the outfit at temp 0 in the callee's `STR#` 304 the default daywear.
    @Test func updatesTheDefaultDaywear() throws {
        try withHands { vm, sim, _, _ throws in
            sim.thread.tempRegisters[0] = 1
            #expect(try vm.runPrimitive(opcode: 6, operand: suit(0, scope: 2, flags: 4), caller: sim).0 == .gotoTrue)
            #expect(sim.sim.daywear == 0x1A_0000_000D && sim.sim.bodyOutfit == 0x1A_0000_000D)
            sim.thread.tempRegisters[0] = 2
            #expect(throws: SimAnticsError.self) { try vm.runPrimitive(opcode: 6, operand: suit(0, scope: 2, flags: 4), caller: sim) }
        }
    }
}

@Suite struct HandOperandTests {
    /// The operands read and write as FreeSO's `VMReachOperand` and `VMChangeSuitOrAccessoryOperand`.
    @Test func operandsRoundTrip() {
        let reach = Primitives.Reach.Operand(bytes: [1, 0, 2, 0, 3, 0, 0, 0])
        #expect(reach.mode == 1 && reach.grabOrDrop == 2 && reach.slotParameter == 3)
        #expect(reach.encoded() == [1, 0, 2, 0, 3, 0, 0, 0])
        let suit = Primitives.ChangeSuitOrAccessory.Operand(bytes: [3, 2, 0x01, 0x80, 0, 0, 0, 0])
        #expect(suit.suitData == 3 && suit.suitScope == 2 && suit.flags == 0x8001 && suit.removes && !suit.updatesDaywear)
        #expect(suit.encoded() == [3, 2, 0x01, 0x80, 0, 0, 0, 0])
        #expect(PrimitiveTable.unportedOperand(opcode: 4, bytes: []) == nil && PrimitiveTable.unportedOperand(opcode: 47, bytes: []) == nil)
    }
}
