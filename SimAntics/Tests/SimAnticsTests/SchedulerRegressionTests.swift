import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// A Sim whose own code failed every tick was deleted like a failing object, and the dead Sim kept
/// running from leftover schedule entries, each run scheduling it again, until a tick took minutes.
@Suite struct SchedulerRegressionTests {
    /// An entity scheduled twice for the same tick runs once.
    @Test func anEntityIsScheduledForATickOnce() throws {
        try withVM { vm, chair throws in
            vm.scheduler.scheduleTick(for: chair, in: 1)
            vm.scheduler.scheduleTick(for: chair, in: 1)
            #expect(vm.scheduler.scheduledObjectIDs(on: vm.scheduler.currentTick + 1) == [chair.objectID])
        }
    }

    /// A deleted entity is never scheduled, and never runs, again.
    @Test func aDeletedEntityNeverRunsAgain() throws {
        try withVM(chair: [bhavChunk(id: 4096, [addToAttribute(0, 1)])], chairWords: [mainWord: 4096]) { vm, chair throws in
            try chair.initialize()
            vm.tick()
            let runs = chair.attribute(at: 0)
            try vm.delete(chair)
            vm.scheduler.scheduleTick(for: chair, in: 1)
            #expect(vm.scheduler.scheduledObjectIDs(on: vm.scheduler.currentTick + 1).isEmpty)
            chair.tick()
            chair.reset()
            #expect(chair.attribute(at: 0) == runs && chair.thread.stack.isEmpty)
        }
    }

    /// A Sim whose code fails tick after tick is reset each time, but stays on the lot; only
    /// objects are deleted for failing again so soon.
    @Test func aFailingSimIsntDeleted() throws {
        let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
        let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
        try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
        let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Failing", persistID: 9, bodyOutfit: 0)))
        var failing = expression(.assign, .temps, 0, .literal, 1)
        failing[5] = 20 // no such operator
        let routine = Routine(id: 4096, instructions: [
            Instruction(index: 0, opcode: 2, truePointer: 254, falsePointer: 255,
                        operand: PrimitiveTable.standard.decode(opcode: 2, operand: failing)),
        ])
        try withExtendedLifetime(vm) {
            for _ in 0..<5 {
                sim.thread.stack = [StackFrame(thread: sim.thread, routine: routine, caller: sim, callee: sim, codeOwner: sim.object)]
                vm.tick()
            }
            #expect(!sim.isDead && vm.entity(id: sim.objectID) === sim)
            let scheduled = vm.scheduler.scheduledObjectIDs(on: vm.scheduler.currentTick + 1)
            #expect(scheduled.filter { $0 == sim.objectID }.count == 1)
        }
    }
}
