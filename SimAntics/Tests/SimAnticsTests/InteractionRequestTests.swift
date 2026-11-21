import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// A player's requests through `VM`'s API, with the mock Sim joined as a visitor and the ball.
@Suite struct InteractionRequestTests {
    private func withSimAndBall(_ body: (VM, Entity, Entity) throws -> Void) throws {
        let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
        let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
        try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
        let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Player", persistID: 9, bodyOutfit: 0)))
        let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
        try withExtendedLifetime(vm) { try body(vm, sim, ball) }
    }

    @Test func offersWhatTheSimMayChoose() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            #expect(try vm.availableInteractions(on: ball, for: sim).map(\.name) == ["Dance With", "Pick Up"])
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(try vm.availableInteractions(on: chair, for: sim).isEmpty, "no table")
            #expect(try sim.placeInSlot(chair, slot: 0, cleanOld: true))
            #expect(try vm.availableInteractions(on: ball, for: sim).isEmpty, "carrying, and neither allows it")
        }
    }

    @Test func queuesAChosenInteractionThatTheSimThenRuns() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            let id = try vm.queueInteraction(0, on: ball, for: sim)
            let action = try #require(sim.thread.queue.first)
            #expect(action.id == id && action.name == "Dance With" && action.priority == QueuedAction.Priority.userDriven)
            #expect(!action.flags.contains(.mustRun), "chosen, not pushed")
            vm.tick()
            vm.tick()
            #expect(sim.sim.animations.first?.clip.name == "mock-dance")
            #expect(vm.cancelInteraction(id: id, for: sim))
            #expect(sim.thread.queue.first?.isCancelled == true)
            #expect(!vm.cancelInteraction(id: id &+ 1, for: sim))
        }
    }

    @Test func turnsDownWhatTheSimCantChoose() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            #expect(throws: InteractionRequestError.noInteraction(7)) { try vm.queueInteraction(7, on: ball, for: sim) }
            #expect(throws: InteractionRequestError.notASim(objectID: ball.objectID)) { try vm.queueInteraction(0, on: sim, for: ball) }
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(try sim.placeInSlot(chair, slot: 0, cleanOld: true))
            #expect(throws: InteractionRequestError.notAllowed(1)) { try vm.queueInteraction(1, on: ball, for: sim) }
            #expect(sim.thread.queue.isEmpty)
        }
    }
}
