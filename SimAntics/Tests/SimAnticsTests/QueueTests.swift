import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// The mock Sim, joined to its lot as a visitor (persist ID 9), and the mock ball out of the world.
/// The Sim's main counts its runs in attribute 0, then runs what's queued with Idle For Input.
/// The VM lives until `body` returns: entities hold it unowned.
private func withSimAndBall(_ body: (VM, Entity, Entity) throws -> Void) throws {
    let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
    let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
    try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
    let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Player", persistID: 9, bodyOutfit: 0)))
    let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
    try withExtendedLifetime(vm) { try body(vm, sim, ball) }
}

/// The ball's interaction with a number ("Dance With" 0, "Pick Up" 1) as an action.
private func action(_ number: Int, on ball: Entity, priority: Int16 = QueuedAction.Priority.userDriven,
                    flags: Interaction.Flags? = nil) throws -> QueuedAction {
    var action = try #require(try QueuedAction(try Interaction.interactions(of: ball.object)[number], of: ball))
    action.priority = priority
    if let flags { action.flags = flags }
    return action
}

@Suite struct QueueTests {
    // MARK: Queueing

    @Test func ordersByPriorityThenArrivalAndNumbersEachAction() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            let thread = sim.thread
            let ids = [
                thread.enqueue(try action(0, on: ball, priority: 50)),
                thread.enqueue(try action(0, on: ball, priority: 50)),
                thread.enqueue(try action(0, on: ball, priority: 100)),
                thread.enqueue(try action(0, on: ball, priority: 2)),
            ]
            #expect(ids == [0, 1, 2, 3])
            #expect(thread.queue.map(\.id) == [2, 0, 1, 3], "higher priorities first, equal ones in turn")
            #expect(thread.queue.allSatisfy { !$0.isCancelled }, "nothing runs, so nothing is cancelled")
        }
    }

    @Test func aLeapfroggingActionGoesRightAfterTheRunningOne() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            let thread = sim.thread
            thread.enqueue(try action(0, on: ball, priority: 100))
            thread.enqueue(try action(0, on: ball, priority: 100))
            thread.activeQueueBlock = 0
            thread.enqueue(try action(0, on: ball, priority: 2, flags: [.leapfrog]))
            #expect(thread.queue.map(\.id) == [0, 2, 1])
        }
    }

    @Test func aMoreUrgentActionCancelsTheRunningOne() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            let thread = sim.thread
            thread.enqueue(try action(0, on: ball))
            thread.activeQueueBlock = 0
            thread.enqueue(try action(0, on: ball, priority: QueuedAction.Priority.maximum))
            #expect(thread.queue.map(\.id) == [0, 1], "the running action stays at the front")
            #expect(thread.queue[0].isCancelled && sim.hasFlag(EntityFlag.interactionCanceled))
        }
    }

    @Test func anActionToRunImmediatelyWaitsHiddenThenRunsFirst() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            let thread = sim.thread
            thread.enqueue(try action(1, on: ball))
            thread.enqueue(try action(0, on: ball, flags: [.runImmediately]))
            #expect(thread.queue[1].mode == .idle && thread.queue[1].priority == .min)
            vm.tick()
            #expect(thread.queue.map(\.id) == [1, 0], "moved to the front")
            #expect(thread.stack.last.map { $0.isActionTree && $0.routine.id == 4098 } == true, "and dancing")
        }
    }

    // MARK: Cancelling

    @Test func cancellingAWaitingActionTakesItOut() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            let thread = sim.thread
            let id = thread.enqueue(try action(0, on: ball))
            #expect(thread.cancelAction(id: id))
            #expect(thread.queue.isEmpty)
            #expect(!thread.cancelAction(id: id), "it's gone")
        }
    }

    @Test func cancellingTheRunningActionFlagsIt() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            let thread = sim.thread
            let id = thread.enqueue(try action(0, on: ball))
            vm.tick()
            #expect(thread.stack.last?.isActionTree == true)
            #expect(thread.cancelAction(id: id))
            #expect(thread.queue.first?.isCancelled == true && thread.queue.first?.priority == 0)
            #expect(sim.hasFlag(EntityFlag.interactionCanceled))
        }
    }

    /// A parent-idle action, running, with another after it and its parent's exit.
    @Test func cancellingAParentIdleActionTakesTheOnesAfterIt() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            let thread = sim.thread
            let actions = try [(QueuedAction.Mode.parentIdle, 10), (.parentIdle, 11), (.parentExit, 12)].map { mode, id in
                var queued = try action(0, on: ball)
                queued.mode = mode
                queued.id = UInt16(id)
                return queued
            }
            thread.queue = actions
            thread.activeQueueBlock = 0
            #expect(thread.cancelAction(id: 10))
            #expect(thread.queue.map(\.id) == [10, 12], "the later parent-idle action goes")
            #expect(thread.queue.allSatisfy { $0.isCancelled && $0.priority == 0 }, "the running one and the exit look cancelled")
            #expect(sim.hasFlag(EntityFlag.interactionCanceled))
        }
    }

    // MARK: Who may run an action

    @Test func aSimMayRunTheBallsInteractions() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            #expect(sim.thread.mayRun(try action(0, on: ball)))
            #expect(sim.thread.mayRun(try action(1, on: ball)), "its check tree returns true")
        }
    }

    @Test func aSimCarryingSomethingMayOnlyRunWhatAllowsIt() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(try sim.placeInSlot(chair, slot: 0, cleanOld: true))
            #expect(!sim.thread.mayRun(try action(0, on: ball)))
            #expect(sim.thread.mayRun(try action(0, on: ball, flags: [.allowVisitors, .availableWhenCarrying])))
        }
    }

    @Test func petsRunOnlyPetActionsOfTheirKind() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            #expect(!sim.thread.mayRun(try action(0, on: ball, flags: [.allowVisitors, .allowCats])), "people don't")
            sim.sim.kind = .cat
            #expect(!sim.thread.mayRun(try action(0, on: ball)))
            #expect(sim.thread.mayRun(try action(0, on: ball, flags: [.allowVisitors, .allowCats])))
            #expect(!sim.thread.mayRun(try action(0, on: ball, flags: [.allowVisitors, .allowDogs])))
        }
    }

    /// A visitor is barred where the permissions leave visitors out, unless it owns the object.
    @Test func permissionsBarVisitorsWhoDontOwnTheObject() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            var roommatesOnly = try action(0, on: ball, flags: [])
            roommatesOnly.permissions = [.objectOwner, .roommates]
            #expect(!sim.thread.mayRun(roommatesOnly))
            ball.ownerID = 9
            #expect(sim.thread.mayRun(roommatesOnly), "the owner may")
            ball.ownerID = 0
            sim.sim.permissions = .roommate
            #expect(sim.thread.mayRun(roommatesOnly))
        }
    }

    @Test func debugActionsAreForAdmins() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            let debug = try action(0, on: ball, flags: [.debug])
            #expect(!sim.thread.mayRun(debug))
            sim.sim.permissions = .admin
            #expect(sim.thread.mayRun(debug))
        }
    }

    @Test func aCheckTreeThatReturnsFalseBarsTheAction() throws {
        try withSimAndBall { (_: VM, sim: Entity, ball: Entity) throws in
            var pickUp = try action(1, on: ball)
            // 0 > 0, which is false: return false.
            guard case .primitive(let never) = PrimitiveTable.standard.decode(opcode: 2, operand: [0, 0, 0, 0, 0, 0, 7, 7]) else {
                Issue.record("Expression doesn't decode")
                return
            }
            pickUp.checkTree = Routine(id: 4096, instructions: [
                Instruction(index: 0, opcode: 2, truePointer: 254, falsePointer: 255, operand: .primitive(never)),
            ])
            #expect(!sim.thread.mayRun(pickUp))
            pickUp.flags = [.allowVisitors, .mustRun]
            #expect(sim.thread.mayRun(pickUp), "an action that must run isn't checked")
        }
    }

    // MARK: Running

    /// The Sim's main hands over to "Dance With", which plays `mock-dance` to its end, two seconds,
    /// and returns to the queue; main then carries on counting its runs.
    @Test func theSimDancesWithTheBallThenCarriesOn() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            vm.tick()
            let runsBefore = sim.attribute(at: 0)
            sim.thread.enqueue(try action(0, on: ball))
            #expect(ball.users.map(\.objectID) == [sim.objectID])
            #expect(try ball.value(of: ObjectVariable.useCount.rawValue) == 1)

            vm.tick()   // main pushes the dance
            vm.tick()   // the dance starts
            #expect(sim.thread.stack.last?.isActionTree == true && sim.thread.activeQueueBlock == 0)
            #expect(sim.sim.animations.first?.clip.name == "mock-dance")
            let runsWhileDancing = sim.attribute(at: 0)
            #expect(runsWhileDancing == runsBefore &+ 1, "main waits while the dance runs")

            var ticks = 0
            while !sim.thread.queue.isEmpty && ticks < 200 {
                vm.tick()
                ticks += 1
            }
            #expect(sim.thread.queue.isEmpty && sim.thread.activeQueueBlock == -1)
            #expect((55...65).contains(ticks), "about 60 ticks of dancing, took \(ticks)")
            #expect(sim.sim.animations.isEmpty)
            vm.tick()
            #expect(sim.attribute(at: 0) > runsWhileDancing, "main runs again")
            #expect(vm.reportedErrors.isEmpty)
        }
    }

    /// "Pick Up": Reach takes the ball in hand on its event 0, the ball's `CT - Grab` runs by name
    /// (attribute 1 of the ball, the interaction's object), and Drop puts it down beside the Sim.
    @Test func theSimPicksUpTheBallAndItsCallbackRuns() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            #expect(try vm.place(ball.group, at: .center(ofTileX: 4, y: 3, level: 1), facing: .north).status == .success)
            sim.thread.enqueue(try action(1, on: ball))
            var ticks = 0
            var held = false
            while !sim.thread.queue.isEmpty && ticks < 200 {
                vm.tick()
                if sim.slot(0) === ball { held = true }
                ticks += 1
            }
            #expect(held, "the reach took the ball")
            #expect(sim.thread.queue.isEmpty && ball.attribute(at: 1) == 1, "CT - Grab ran once")
            #expect(ball.container == nil && !ball.position.isOutOfWorld && sim.slot(0) == nil, "dropped beside the Sim")
            #expect(vm.reportedErrors.isEmpty, "\(vm.reportedErrors)")
        }
    }

    @Test func anInteractionsObjectGoingAwayResetsTheSim() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            sim.thread.enqueue(try action(0, on: ball))
            vm.tick()
            vm.tick()
            #expect(sim.thread.stack.last?.isActionTree == true)
            try vm.delete(ball)
            vm.tick()
            #expect(sim.thread.queue.isEmpty && sim.thread.stack.allSatisfy { !$0.isActionTree })
        }
    }

    @Test func aCancelledInteractionEndsItsIdleForInput() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            var waiting = try action(0, on: ball)
            waiting.isCancelled = true
            sim.thread.queue = [waiting]
            let idle = Primitives.IdleForInput.Operand(argument: 0).encoded()
            let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 17, operand: idle, caller: sim, arguments: [100, 0, 0, 0])
            frame.isActionTree = true
            #expect(try primitive.execute(in: frame) == .gotoTrue)
            #expect(sim.hasFlag(EntityFlag.notifiedByIdleForInput))
        }
    }

    @Test func theHurryFlagEndsAnAnimationOnInput() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            sim.thread.queue = [try action(0, on: ball)]
            let hurried = Primitives.AnimateSim.Operand(animationID: 2, flags: 8, expectedEventCount: 2).encoded()
            let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 44, operand: hurried, caller: sim)
            frame.isActionTree = true
            #expect(try primitive.execute(in: frame) == .continueNextTick, "it starts")
            sim.advanceAnimations()
            #expect(try primitive.execute(in: frame) == .continueNextTick, "not cancelled: it plays on")
            sim.thread.queue[0].isCancelled = true
            #expect(try primitive.execute(in: frame) == .gotoFalse && frame.arguments[0] == 0, "missing events are made up")
            #expect(try primitive.execute(in: frame) == .gotoFalse && frame.arguments[0] == 1)
            #expect(try primitive.execute(in: frame) == .gotoTrue && sim.sim.animations.isEmpty)

            sim.thread.queue[0].isCancelled = false
            sim.personData[PersonData.nonInterruptable] = 1
            #expect(try primitive.execute(in: frame) == .continueNextTick)
            sim.thread.queue[0].isCancelled = true
            #expect(try primitive.execute(in: frame) == .continueNextTick, "a non-interruptable Sim isn't hurried")
        }
    }

    @Test func testSimInteractingWithReadsTheRunningInteraction() throws {
        try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
            func test() throws -> ExitCode {
                let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 37, operand: [], caller: sim, stackObjectID: ball.objectID)
                defer { sim.thread.stack.removeLast() }
                return try primitive.execute(in: frame)
            }
            #expect(try test() == .gotoFalse, "nothing queued")
            sim.thread.enqueue(try action(0, on: ball))
            #expect(try test() == .gotoFalse, "queued, but main is running")
            vm.tick()   // main pushes the dance
            let (primitive, frame) = try vm.makePrimitiveFrame(opcode: 37, operand: [], caller: sim, stackObjectID: ball.objectID)
            frame.isActionTree = true
            #expect(try primitive.execute(in: frame) == .gotoTrue)
            frame.stackObject = sim
            #expect(try primitive.execute(in: frame) == .gotoFalse, "another object")
        }
    }

    @Test func runningTheSameLotTwiceGivesTheSameDigests() throws {
        func run() throws -> [String] {
            var digests: [String] = []
            try withSimAndBall { (vm: VM, sim: Entity, ball: Entity) throws in
                sim.thread.enqueue(try action(0, on: ball))
                sim.thread.enqueue(try action(1, on: ball, priority: 2))
                digests = (0..<120).map { _ in vm.tick(); return StateDigest.hex(of: vm) }
            }
            return digests
        }
        #expect(try run() == run())
    }
}
