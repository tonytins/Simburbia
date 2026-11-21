import Testing
import TSOContent
import TSOFiles
@testable import SimAntics

let mockBallGUID: UInt32 = 0x4D4F_4308

/// Interactions read from an object's `TTAB` and `TTAs`, and actions in a Sim's queue, on the mock
/// install's ball (see its README).
@Suite struct InteractionTests {
    private func vm() throws -> VM {
        try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
    }

    @Test func readsTheBallsInteractionsWithTheirNames() throws {
        let vm = try vm()
        let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
        let interactions = try Interaction.interactions(of: ball.object)
        #expect(interactions.map(\.name) == ["Dance With", "Pick Up"])
        #expect(interactions.map(\.number) == [0, 1])
        #expect(interactions.map(\.actionTree) == [4098, 4099] && interactions.map(\.checkTree) == [0, 8192])
        #expect(interactions.allSatisfy { $0.flags == .allowVisitors && $0.joiningIndex == -1 })
        #expect(interactions[0].permissions == .everyoneButGhostsAndStaff)
        #expect(interactions[1].permissions == [.objectOwner, .roommates, .visitors])
        let advertisement = try #require(interactions[1].motiveAdvertisements.first)
        #expect(interactions[1].motiveAdvertisements.count == 1 && interactions[0].motiveAdvertisements.isEmpty)
        #expect((advertisement.effectRangeMinimum, advertisement.effectRangeMaximum, advertisement.personalityModifier) == (0, 20, 0))
    }

    @Test func anObjectWithoutATableHasNoInteractions() throws {
        let vm = try vm()
        let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
        #expect(try Interaction.interactions(of: chair.object).isEmpty)
    }

    /// An interaction's action is user-driven, on the object, with its routines resolved through
    /// the object's files: its own action tree, and the semi-global's check tree.
    @Test func anInteractionBecomesAQueuedAction() throws {
        let vm = try vm()
        let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
        let interactions = try Interaction.interactions(of: ball.object)

        let dance = try #require(try QueuedAction(interactions[0], of: ball))
        #expect(dance.actionTree.id == 4098 && dance.checkTree == nil)
        #expect(dance.callee === ball && dance.stackObject === ball && dance.codeOwner.guid == mockBallGUID)
        #expect(dance.name == "Dance With" && dance.interactionNumber == 0 && dance.arguments == [0, 0, 0, 0])
        #expect(dance.priority == QueuedAction.Priority.userDriven && dance.mode == .normal && !dance.isCancelled)

        let pickUp = try #require(try QueuedAction(interactions[1], of: ball))
        #expect(pickUp.actionTree.id == 4099 && pickUp.checkTree?.id == 8192)
        #expect(pickUp.permissions == [.objectOwner, .roommates, .visitors])
    }

    @Test func anInteractionWhoseActionTreeIsMissingGivesNoAction() throws {
        let vm = try vm()
        let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
        var missing = try #require(try Interaction.interactions(of: ball.object).first)
        missing.actionTree = 4200
        #expect(try QueuedAction(missing, of: ball) == nil)
    }

    @Test func anActionRunsAsAnInteractionsFrame() throws {
        let vm = try vm()
        let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
        let sim = try #require(try vm.createObject(guid: mockSimGUID)?.objects.first)
        var action = try #require(try QueuedAction(try Interaction.interactions(of: ball.object)[1], of: ball))
        action.arguments = [3, 0, 0, 0]
        let frame = action.frame(on: sim.thread)
        #expect(frame.thread === sim.thread && frame.caller === sim && frame.callee === ball && frame.stackObject === ball)
        #expect(frame.isActionTree && frame.routine.id == 4099 && frame.arguments == [3, 0, 0, 0])
    }

    /// The digest covers each queued action: a Sim with one hashes differently from one without,
    /// and the readable lines show it. A Sim with an empty queue digests as before.
    @Test func theDigestCoversTheQueue() throws {
        let vm = try vm()
        let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
        let sim = try #require(try vm.createObject(guid: mockSimGUID)?.objects.first)
        let empty = StateDigest.hex(of: vm)
        #expect(StateDigest.lines(of: vm).last?.hasSuffix(" queue=") == true)

        var action = try #require(try QueuedAction(try Interaction.interactions(of: ball.object)[0], of: ball))
        action.id = 7
        sim.thread.queue = [action]
        let queued = StateDigest.hex(of: vm)
        #expect(queued != empty)
        #expect(StateDigest.lines(of: vm).last?.hasSuffix(" queue=4098:\(ball.objectID):0:50:0:7") == true)

        sim.thread.queue[0].isCancelled = true
        #expect(StateDigest.hex(of: vm) != queued)
        #expect(StateDigest.lines(of: vm).last?.hasSuffix(":7c") == true)
    }

    /// A table the object's file doesn't have is read from its semi-global, with the strings
    /// beside it there.
    @Test func readsATableFromTheSemiGlobal() throws {
        var table = ByteWriter()
        table.uint16(1); table.uint16(8)
        table.uint16(4096); table.uint16(0); table.uint32(0); table.uint32(0); table.uint32(0); table.uint32(0)
        table.uint32(0); table.uint32(0); table.int32(-1)
        var strings = ByteWriter()
        strings.int16(-2); strings.uint16(1); strings.ascii("Shared"); strings.uint8(0); strings.uint8(0)
        try withVM(chairWords: [5: 200], semiGlobal: [ChunkFixture(type: "TTAB", id: 200, contents: table.bytes),
                                                      ChunkFixture(type: "TTAs", id: 200, contents: strings.bytes)]) { _, chair in
            let interactions = try Interaction.interactions(of: chair.object)
            #expect(interactions.map(\.name) == ["Shared"] && interactions.first?.actionTree == 4096)
        }
    }

    @Test func aTableThatDoesntParseIsAnError() throws {
        var bad = ByteWriter()
        bad.uint16(1); bad.uint16(9); bad.uint8(2); bad.uint8(0)
        try withVM(chair: [ChunkFixture(type: "TTAB", id: 128, contents: bad.bytes)], chairWords: [5: 128]) { _, chair in
            #expect(throws: SimAnticsError.self) { try Interaction.interactions(of: chair.object) }
        }
    }
}
