import Foundation
import Testing
import TSOContent
import TSOFiles
@testable import SimAntics

@Suite struct LookTowardsTests {
    /// The mock Sim joined to its lot, and a chair. The VM lives until `body` returns.
    private func withSim(_ body: (VM, Entity) throws -> Void) throws {
        let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
        let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
        try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
        let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Looker", persistID: 9, bodyOutfit: 0)))
        try withExtendedLifetime(vm) { try body(vm, sim) }
    }

    private func look(_ mode: UInt8, in vm: VM, caller: Entity) throws -> ExitCode {
        let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 22, operand: Primitives.LookTowards.Operand(mode: mode).encoded(),
                                                           caller: caller)
        defer { caller.thread.stack.removeLast() }
        return try primitive.execute(in: frame)
    }

    @Test func theHeadAndTheCameraModesGoTrueAndTurnNothing() throws {
        try withSim { (vm: VM, sim: Entity) throws in
            let facing = sim.direction
            #expect(try look(0, in: vm, caller: sim) == .gotoTrue)
            #expect(try look(1, in: vm, caller: sim) == .gotoTrue)
            #expect(sim.direction == facing)
        }
    }

    @Test func turningTheBodyWaitsForRoutingAndObjectsCantLook() throws {
        try withSim { (vm: VM, sim: Entity) throws in
            #expect(throws: SimAnticsError.unsupported("Look Towards mode 2 (routing, phase E)")) { try look(2, in: vm, caller: sim) }
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(throws: SimAnticsError.invalidCast("Look Towards' caller isn't a Sim")) { try look(0, in: vm, caller: chair) }
        }
    }

    @Test func theOperandEncodesBackToItsBytes() {
        #expect(Primitives.LookTowards.Operand(bytes: [3, 0, 0, 0, 0, 0, 0, 0]).encoded() == [3, 0, 0, 0, 0, 0, 0, 0])
    }
}

/// TSO's own refusal on a real install: the global's "Refuse Moody?" lets a Sim in a good enough
/// mood go on (true) and turns one in a bad mood away (false), playing its refusal.
@Suite(.enabled(if: gameDirectory != nil, "TSO_GAME_DIR is not set"))
struct RefusalTests {
    /// Runs the global routine labelled `label` on a joined template person with `mood`, the
    /// threshold in its parameter, and returns how it exited and whether the Sim animated.
    private func refuse(_ label: String, mood: Int16, threshold: Int16) throws -> (ExitCode, Bool) {
        let content = try GameContent(.init(gameDirectory: try required(gameDirectory)))
        let vm = try VM(content: content, seed: 1)
        _ = try vm.load(try Blueprint(xml: Data("<house><size>77</size><category>0</category></house>".utf8)))
        var identity = SimIdentity(name: "Refuser", persistID: 0x0AC1_E001, bodyOutfit: 0x24C_0000_000D)
        identity.motives = [Int16](repeating: 50, count: 16)
        let sim = try #require(try vm.joinSim(template: 0x7FD9_6B54, identity: identity))
        let bhav = try #require(try vm.global.chunks(BHAV.self).first { $0.label == label }, "no global \(label)")
        let routine = try #require(try vm.routine(opcode: bhav.id, codeOwner: sim.object))
        return try withExtendedLifetime(vm) {
            sim.motiveData[Motive.mood] = mood
            sim.thread.stack.removeAll()
            let frame = StackFrame(thread: sim.thread, routine: routine, caller: sim, callee: sim, codeOwner: sim.object)
            frame.arguments = [threshold, 0, 0, 0]
            sim.thread.push(frame)
            var animated = false
            for _ in 0..<600 {
                vm.tick()
                if !sim.sim.animations.isEmpty { animated = true }
                if !sim.thread.stack.contains(where: { $0 === frame }) { break }
            }
            #expect(!sim.thread.stack.contains(where: { $0 === frame }), "the routine ended")
            #expect(vm.reportedErrors.isEmpty, "\(vm.reportedErrors.map(\.error))")
            return (sim.thread.lastExitCode, animated)
        }
    }

    @Test func aSimInAGoodMoodGoesOn() throws {
        let (exit, animated) = try refuse("Refuse Moody?", mood: 50, threshold: 0)
        #expect(exit == .returnTrue && !animated)
    }

    @Test func aSimInABadMoodRefuses() throws {
        let (exit, animated) = try refuse("Refuse Moody?", mood: -50, threshold: 0)
        #expect(exit == .returnFalse && animated)
    }
}
