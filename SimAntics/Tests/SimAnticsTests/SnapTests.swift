import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// Snap's stand-in mode 2, on `mock-lot-sim.xml` with the mock Sim joined on 3,3 and the chair on
/// 4,4. The VM lives until `body` returns.
private func withJoinedSim(_ body: (VM, Entity) throws -> Void) throws {
    let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
    let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
    try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
    let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Sleeper", persistID: 9, bodyOutfit: 0)))
    try withExtendedLifetime(vm) { try body(vm, sim) }
}

/// Runs Snap once, the Sim as caller, with a stack object.
private func snap(_ operand: Primitives.Snap.Operand, in vm: VM, sim: Entity, stackObject: Entity) throws -> ExitCode {
    let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 46, operand: operand.encoded(), caller: sim,
                                                       stackObjectID: stackObject.objectID)
    defer { sim.thread.stack.removeLast() }
    return try primitive.execute(in: frame)
}

@Suite struct SnapTests {
    @Test func theOperandEncodesBackToItsBytes() {
        #expect(Primitives.Snap.Operand(bytes: [6, 0, 1, 0, 3, 0, 0, 0]) == .init(index: 6, mode: 1, flags: 3))
        #expect(Primitives.Snap.Operand(index: 6, mode: 1, flags: 3).encoded() == [6, 0, 1, 0, 3, 0, 0, 0])
    }

    /// Facing east, a Sim snapped in front of itself moves one tile east and keeps its facing.
    @Test func movesTheSimInFrontOfTheStackObject() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            #expect(sim.position == .center(ofTileX: 3, y: 3, level: 1))
            sim.direction = .east
            #expect(try snap(.init(mode: 2), in: vm, sim: sim, stackObject: sim) == .gotoTrue)
            #expect(sim.position == .center(ofTileX: 4, y: 3, level: 1) && sim.direction == .east)
        }
    }

    @Test func offTheLotItFailsAndSaysSo() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
            try vm.move(ball, to: .center(ofTileX: 0, y: 0, level: 1))
            ball.direction = .north
            #expect(try snap(.init(mode: 2), in: vm, sim: sim, stackObject: ball) == .gotoFalse)
            #expect(try sim.value(of: ObjectVariable.primitiveResult.rawValue) == 2)
            #expect(sim.position == .center(ofTileX: 3, y: 3, level: 1), "the Sim stays where it was")
        }
    }

    @Test func otherModesWaitForRouting() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            #expect(throws: SimAnticsError.unsupported("Snap mode 3 (routing, phase E)")) {
                try snap(.init(index: 1, mode: 3), in: vm, sim: sim, stackObject: sim)
            }
        }
    }
}
