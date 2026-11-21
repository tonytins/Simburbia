import Foundation
import Testing
import TSOContent
import TSOFiles
@testable import SimAntics

/// The mock Sim on its lot. Its animation table (STR# 129) names, from 1: mock-stand (an xevt 1
/// at frame 15, 30 frames), mock-dance (xevts 1 and 2 at frames 15 and 45, 60 frames),
/// mock-walk, and mock-missing, which no file has.
private func mockSim() throws -> (VM, Entity) {
    let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
    let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
    try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
    let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Dancer", persistID: 9, bodyOutfit: 0)))
    return (vm, sim)
}

private func animate(_ operand: Primitives.AnimateSim.Operand) -> [UInt8] { operand.encoded() }

/// Runs Animate Sim once a tick, the Sim's animations advancing after it as in a real tick, until
/// it goes true; returns each run's exit code, with the event it gave on a false.
private func playToTheEnd(_ operand: Primitives.AnimateSim.Operand, on sim: Entity, in vm: VM,
                          locals: [Int16] = []) throws -> [String] {
    var runs: [String] = []
    for _ in 0..<500 {
        let (code, frame) = try vm.runPrimitive(opcode: 44, operand: animate(operand), caller: sim, locals: locals)
        switch code {
        case .gotoFalse:
            runs.append("event \(operand.storesEventInLocal ? frame.locals[Int(operand.localEventNumber)] : frame.arguments[0])")
        case .gotoTrue:
            runs.append("true")
            return runs
        default:
            if runs.last != "wait" { runs.append("wait") }
        }
        sim.advanceAnimations()
    }
    return runs
}

@Suite struct AnimateSimTests {
    /// Play and wait: start, wait, hand over each event as it fires, then go true at the end and
    /// stop the animation.
    @Test func playsAndWaitsHandingOverEachEvent() throws {
        let (vm, sim) = try mockSim()
        #expect(try playToTheEnd(.init(animationID: 1), on: sim, in: vm) == ["wait", "event 1", "wait", "true"])
        #expect(sim.sim.animations.isEmpty)
    }

    /// With flag 32 the event goes into the local the operand names.
    @Test func putsTheEventInALocal() throws {
        let (vm, sim) = try mockSim()
        let operand = Primitives.AnimateSim.Operand(animationID: 2, localEventNumber: 1, flags: 32)
        #expect(try playToTheEnd(operand, on: sim, in: vm, locals: [0, 0]) == ["wait", "event 1", "wait", "event 2", "wait", "true"])
        // A local past the frame's is an error, not a trap.
        sim.sim.animations = []
        _ = try vm.runPrimitive(opcode: 44, operand: animate(operand), caller: sim, locals: [0, 0])
        for _ in 1...20 { sim.advanceAnimations() }
        #expect(throws: SimAnticsError.indexOutOfRange("local 3")) {
            try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 2, localEventNumber: 3, flags: 32)), caller: sim)
        }
    }

    /// An animation that ends having run fewer events than expected makes up the rest, numbered
    /// from the count run so far (the bath's drain needs this).
    @Test func makesUpExpectedEventsAtTheEnd() throws {
        let (vm, sim) = try mockSim()
        let runs = try playToTheEnd(.init(animationID: 2, expectedEventCount: 4), on: sim, in: vm)
        #expect(runs == ["wait", "event 1", "wait", "event 2", "wait", "event 2", "event 3", "true"])
    }

    /// Backwards, the dance's events come last first.
    @Test func playsBackwards() throws {
        let (vm, sim) = try mockSim()
        #expect(try playToTheEnd(.init(animationID: 2, flags: 2), on: sim, in: vm) == ["wait", "event 2", "wait", "event 1", "wait", "true"])
    }

    /// A name with no animation, or an ID past the table, plays nothing and goes true; so does a
    /// source with no table.
    @Test func goesTrueWithoutAnAnimation() throws {
        let (vm, sim) = try mockSim()
        for operand in [Primitives.AnimateSim.Operand(animationID: 4), .init(animationID: 99), .init(animationID: 1, source: 1),
                        .init(animationID: 1, source: 9)] {
            #expect(try vm.runPrimitive(opcode: 44, operand: animate(operand), caller: sim).0 == .gotoTrue, "\(operand)")
            #expect(sim.sim.animations.isEmpty)
        }
    }

    /// Another animation replaces the one playing.
    @Test func anotherAnimationReplacesTheOnePlaying() throws {
        let (vm, sim) = try mockSim()
        _ = try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 1)), caller: sim)
        for _ in 1...5 { sim.advanceAnimations() }
        sim.sim.leftHandPose = 2
        #expect(try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 2)), caller: sim).0 == .continueNextTick)
        #expect(sim.sim.animations.map(\.clip.key) == ["mock-dance"] && sim.sim.animations[0].frame == 0)
        #expect(sim.sim.leftHandPose == 0)
    }

    /// Mode 2 sets the carry animation; mode 3 clears it, then plays and waits; mode 1 does nothing.
    @Test func carryAndBackgroundModes() throws {
        let (vm, sim) = try mockSim()
        #expect(try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 1, flags: 16)), caller: sim).0 == .gotoTrue)
        #expect(sim.sim.carryAnimation?.clip.key == "mock-stand" && sim.sim.animations.isEmpty)
        #expect(try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 2, flags: 17)), caller: sim).0 == .continueNextTick)
        #expect(sim.sim.carryAnimation == nil && sim.sim.animations.map(\.clip.key) == ["mock-dance"])
        sim.sim.animations = []
        #expect(try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 1, flags: 1)), caller: sim).0 == .gotoTrue)
        #expect(sim.sim.animations.isEmpty && sim.sim.carryAnimation == nil)
    }

    /// ID 0 stops everything and loops the posture's walk animation; with none, it only stops.
    @Test func idZeroResetsToThePosturesWalk() throws {
        let (vm, sim) = try mockSim()
        _ = try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 1)), caller: sim)
        sim.sim.carryAnimation = AnimationState(clip: try #require(try vm.animationClip(named: "mock-stand")))
        // The mock's walk table has two entries, so standing (3) has none.
        #expect(try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 0)), caller: sim).0 == .gotoTrue)
        #expect(sim.sim.animations.isEmpty && sim.sim.carryAnimation != nil)
        sim.sim.walkAnimations[3] = "mock-walk"
        #expect(try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 0)), caller: sim).0 == .gotoTrue)
        #expect(sim.sim.animations.map(\.clip.key) == ["mock-walk"] && sim.sim.animations[0].loops)
        // Holding nothing, the carry animation goes.
        #expect(sim.sim.carryAnimation == nil)
    }

    /// From a parameter, the ID names the stack object's table when the source is the object.
    @Test func takesTheIDFromAParameterAndTheStackObjectsTable() throws {
        let (vm, sim) = try mockSim()
        let operand = Primitives.AnimateSim.Operand(animationID: 2, flags: 4)
        let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 44, operand: animate(operand), caller: sim,
                                                           arguments: [0, 0, 2, 0], stackObjectID: sim.objectID)
        #expect(try primitive.execute(in: frame) == .continueNextTick)
        #expect(sim.sim.animations.map(\.clip.key) == ["mock-dance"])
        sim.thread.stack.removeAll()
        sim.sim.animations = []
        // With no stack object, there's no table.
        let (bare, _) = try vm.runPrimitive(opcode: 44, operand: animate(operand), caller: sim, arguments: [0, 0, 2, 0])
        #expect(bare == .gotoTrue && sim.sim.animations.isEmpty)
        #expect(throws: SimAnticsError.indexOutOfRange("parameter 7")) {
            try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 7, flags: 4)), caller: sim)
        }
    }

    /// Only a Sim can animate.
    @Test func anObjectCantAnimate() throws {
        let (vm, _) = try mockSim()
        let chair = try #require(try vm.createObject(guid: 0x4D4F_4301)?.objects.first)
        #expect(throws: SimAnticsError.self) { try vm.runPrimitive(opcode: 44, operand: animate(.init(animationID: 1)), caller: chair) }
    }

    @Test func theOperandReadsAsFreeSOReadsIt() {
        let operand = Primitives.AnimateSim.Operand(bytes: [0x10, 0, 2, 9, 1, 0x20, 3, 0])
        #expect(operand.animationID == 16 && operand.localEventNumber == 2 && operand.source == 1)
        #expect(operand.flags == 0x20 && operand.expectedEventCount == 3 && operand.storesEventInLocal && operand.mode == 0)
        // The byte after the event number is padding, written back as zero.
        #expect(operand.encoded() == [0x10, 0, 2, 0, 1, 0x20, 3, 0])
        #expect(Primitives.AnimateSim.Operand(bytes: [0, 0, 0, 0, 0, 0x11, 0, 0]).mode == 3)
    }
}
