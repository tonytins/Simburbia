import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// The mock Sim, joined as a visitor, and the mock ball, for Push Interaction and Change Action
/// String. The VM lives until `body` returns.
private func withSimAndBall(_ body: (VM, Entity, Entity) throws -> Void) throws {
    let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
    let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
    try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
    let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Player", persistID: 9, bodyOutfit: 0)))
    let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
    try withExtendedLifetime(vm) { try body(vm, sim, ball) }
}

private typealias Push = Primitives.PushInteraction.Operand

/// Runs Push Interaction once with the Sim as caller and stack object.
private func push(_ operand: Push, in vm: VM, sim: Entity, locals: [Int16] = [], arguments: [Int16],
                  actionTree: Bool = false) throws -> ExitCode {
    let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 13, operand: operand.encoded(), caller: sim, locals: locals,
                                                       arguments: arguments, stackObjectID: sim.objectID)
    frame.isActionTree = actionTree
    defer { sim.thread.stack.removeLast() }
    return try primitive.execute(in: frame)
}

@Suite struct PushInteractionTests {
    @Test func operandsEncodeBackToTheirBytes() {
        #expect(Push(bytes: [5, 1, 2, 3, 4, 0, 0, 0]).encoded() == [5, 1, 2, 3, 4, 0, 0, 0])
        let change = Primitives.ChangeActionString.Operand(bytes: [0x2D, 0x01, 1, 0, 9, 0, 0, 0])
        #expect(change == .init(stringTable: 0x12D, scope: 1, stringID: 9) && change.encoded() == [0x2D, 0x01, 1, 0, 9, 0, 0, 0])
    }

    @Test func queuesTheObjectsInteractionOnTheStackObject() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            #expect(try push(Push(interaction: 0, objectLocation: 1, priority: 3), in: vm, sim: sim, arguments: [0, ball.objectID, 0, 0])
                == .gotoTrue)
            let action = try #require(sim.thread.queue.first)
            #expect(action.callee === ball && action.name == "Dance With" && action.interactionNumber == 0)
            #expect(action.priority == QueuedAction.Priority.userDriven && action.mode == .normal)
            #expect(action.flags.contains(.mustRun))
        }
    }

    @Test func readsTheObjectFromALocalWithFlagTwo() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            let operand = Push(interaction: 1, objectLocation: 2, priority: 2, flags: 2)
            #expect(try push(operand, in: vm, sim: sim, locals: [0, 0, ball.objectID], arguments: [0, 0, 0, 0]) == .gotoTrue)
            #expect(sim.thread.queue.map(\.name) == ["Pick Up"] && sim.thread.queue[0].priority == QueuedAction.Priority.autonomous)
        }
    }

    @Test func prioritiesAndModes() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            func pushed(_ priority: UInt8, actionTree: Bool = false) throws -> QueuedAction? {
                sim.thread.queue = []
                _ = try push(Push(interaction: 0, objectLocation: 0, priority: priority), in: vm, sim: sim,
                             arguments: [ball.objectID, 0, 0, 0], actionTree: actionTree)
                return sim.thread.queue.last
            }
            #expect(try pushed(0)?.priority == 1, "inherited, outside an interaction")
            #expect(try pushed(1)?.priority == QueuedAction.Priority.maximum)
            #expect(try pushed(4).map { $0.priority == QueuedAction.Priority.parentIdle && $0.mode == .parentIdle } == true)
            #expect(try pushed(5).map { $0.priority == QueuedAction.Priority.parentExit && $0.mode == .parentExit } == true)
            #expect(try pushed(6).map { $0.priority == QueuedAction.Priority.idle && $0.mode == .idle } == true)
            #expect(try pushed(9).map { $0.priority == 0 && $0.mode == .normal } == true, "an unknown priority")

            // Inherited inside an interaction: the running one's, at least 1.
            var running = try #require(try QueuedAction(try vm.interactions(of: ball.object)[0], of: ball))
            running.priority = 40
            sim.thread.queue = [running]
            _ = try push(Push(interaction: 1, objectLocation: 0, priority: 0), in: vm, sim: sim,
                         arguments: [ball.objectID, 0, 0, 0], actionTree: true)
            #expect(sim.thread.queue.last?.priority == 40)
        }
    }

    @Test func continuingTheCurrentOneLeapfrogsAndCarriesItsName() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            var running = try #require(try QueuedAction(try vm.interactions(of: ball.object)[0], of: ball))
            running.name = "Playing Catch"
            sim.thread.queue = [running, running]
            sim.thread.activeQueueBlock = 0
            let operand = Push(interaction: 1, objectLocation: 0, priority: 2, flags: 4 | 8)
            #expect(try push(operand, in: vm, sim: sim, arguments: [ball.objectID, 0, 0, 0], actionTree: true) == .gotoTrue)
            #expect(sim.thread.queue.count == 3)
            #expect(sim.thread.queue[1].flags.contains(.leapfrog) && sim.thread.queue[1].actionTree.id == 4099,
                    "right after the running one")
            #expect(sim.thread.queue[1].name == "Playing Catch")
        }
    }

    @Test func anInteractionTheObjectDoesntHaveIsFalse() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            #expect(try push(Push(interaction: 7, objectLocation: 0, priority: 3), in: vm, sim: sim,
                             arguments: [ball.objectID, 0, 0, 0]) == .gotoFalse)
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(try push(Push(interaction: 0, objectLocation: 0, priority: 3), in: vm, sim: sim,
                             arguments: [chair.objectID, 0, 0, 0]) == .gotoFalse, "no table")
            #expect(sim.thread.queue.isEmpty)
        }
    }

    @Test func aMissingObjectOrLocationIsAnError() throws {
        try withSimAndBall { (vm: VM, sim: Entity, _: Entity) throws in
            #expect(throws: SimAnticsError.nullReference("Push Interaction: no object 999")) {
                try push(Push(interaction: 0, objectLocation: 0, priority: 3), in: vm, sim: sim, arguments: [999, 0, 0, 0])
            }
            #expect(throws: SimAnticsError.indexOutOfRange("local 4")) {
                try push(Push(interaction: 0, objectLocation: 4, priority: 3, flags: 2), in: vm, sim: sim, arguments: [0, 0, 0, 0])
            }
        }
    }

    /// A pushed action must run: it runs even while the Sim carries something, which would bar
    /// the same interaction chosen by a player.
    @Test func aPushedActionRunsWhereAChosenOneCouldnt() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(try sim.placeInSlot(chair, slot: 0, cleanOld: true))
            _ = try push(Push(interaction: 0, objectLocation: 0, priority: 3), in: vm, sim: sim, arguments: [ball.objectID, 0, 0, 0])
            vm.tick()
            vm.tick()
            #expect(sim.thread.stack.last?.isActionTree == true && sim.sim.animations.first?.clip.name == "mock-dance")
        }
    }

    // MARK: Change Action String

    private typealias Change = Primitives.ChangeActionString.Operand

    /// Runs Change Action String with the ball's code; its `STR#` 129 is `["", "mock-dance"]`.
    private func change(_ operand: Change, in vm: VM, sim: Entity, ball: Entity) throws -> ExitCode {
        let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 50, operand: operand.encoded(), caller: sim)
        frame.codeOwner = ball.object
        frame.isActionTree = true
        defer { sim.thread.stack.removeLast() }
        return try primitive.execute(in: frame)
    }

    @Test func renamesTheRunningInteraction() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            sim.thread.queue = [try #require(try QueuedAction(try vm.interactions(of: ball.object)[0], of: ball))]
            #expect(try change(Change(stringTable: 129, stringID: 2), in: vm, sim: sim, ball: ball) == .gotoTrue)
            #expect(sim.thread.queue[0].name == "mock-dance")
            for leaves in [Change(stringTable: 129, stringID: 0), Change(stringTable: 129, stringID: 9), Change(stringTable: 300, stringID: 1)] {
                sim.thread.queue[0].name = "Dance With"
                #expect(try change(leaves, in: vm, sim: sim, ball: ball) == .gotoTrue)
                #expect(sim.thread.queue[0].name == "Dance With", "\(leaves)")
            }
        }
    }

    @Test func withNothingRunningOrAnotherScopeItFails() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            #expect(throws: SimAnticsError.simantics("Change Action String with no interaction running")) {
                try change(Change(stringTable: 129, stringID: 2), in: vm, sim: sim, ball: ball)
            }
            #expect(throws: SimAnticsError.unsupported("Change Action String scope 1")) {
                try change(Change(stringTable: 129, scope: 1, stringID: 2), in: vm, sim: sim, ball: ball)
            }
        }
    }
}
