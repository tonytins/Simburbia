import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// The routing frame's scaffolding (phase E1) and the obstacles routes keep out of.
@Suite struct RoutingFrameTests {
    private func withJoinedSim(_ body: (VM, Entity) throws -> Void) throws {
        let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
        let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
        try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
        let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Walker", persistID: 9, bodyOutfit: 0)))
        try withExtendedLifetime(vm) { try body(vm, sim) }
    }

    private func tile(_ x: Int16, _ y: Int16) -> LotPosition { .center(ofTileX: x, y: y, level: 1) }

    /// A routine with one instruction that returns what the primitive it runs returns.
    private func caller(_ opcode: UInt16, operand: [UInt8], on sim: Entity) -> StackFrame {
        StackFrame(thread: sim.thread, routine: Routine(id: 4096, instructions: [
            Instruction(index: 0, opcode: opcode, truePointer: 254, falsePointer: 255,
                        operand: PrimitiveTable.standard.decode(opcode: opcode, operand: operand)),
        ]), caller: sim, callee: sim, codeOwner: sim.object)
    }

    /// Pushes `route` over a routine that returns what it returns, ticks until that routine has
    /// returned, and gives how many ticks it took and how it returned.
    private func walk(_ route: RoutingFrame, _ sim: Entity, in vm: VM, limit: Int = 600) -> (ticks: Int, exit: ExitCode?) {
        sim.thread.stack.removeAll()
        let frame = caller(2, operand: [0, 0, 0, 0, 0, 2, 7, 7], on: sim)
        sim.thread.push(frame)
        sim.thread.pushRoute(route, from: frame)
        return run(frame, sim, in: vm, limit: limit)
    }

    private func run(_ frame: StackFrame, _ sim: Entity, in vm: VM, limit: Int = 600) -> (ticks: Int, exit: ExitCode?) {
        for tick in 1...limit {
            vm.tick()
            if !sim.thread.stack.contains(where: { $0 === frame }) { return (tick, sim.thread.lastExitCode) }
        }
        return (limit, nil)
    }

    /// A tile north is 16 sixteenths: 160 move frames, up to 8 a tick once the Sim gets going.
    @Test func aSimWalksToItsGoalAtTheWalkingPace() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let (ticks, exit) = walk(RoutingFrame(goals: [RouteGoal(position: tile(3, 2), directions: 4)]), sim, in: vm)
            #expect(exit == .returnTrue && sim.position == tile(3, 2))
            #expect((20...32).contains(ticks), "about two thirds of a second, took \(ticks) ticks")
            #expect(sim.direction == .north && sim.personData[PersonData.routeEntryFlags] == 4)
            #expect(vm.reportedErrors.isEmpty)
        }
    }

    @Test func aSimFacesItsGoalsWayWhenItArrives() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let (_, exit) = walk(RoutingFrame(goals: [RouteGoal(position: tile(3, 2), facing: DeterministicMath.halfPi)]), sim, in: vm)
            #expect(exit == .returnTrue && sim.direction == .east)
        }
    }

    /// A route that can't start returns false, with why in the Sim's `RouteResult`.
    @Test func aRouteThatFailsSaysWhy() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let (_, exit) = walk(RoutingFrame(goals: [RouteGoal(position: tile(7, 7))]), sim, in: vm)
            #expect(exit == .returnFalse && sim.personData[PersonData.routeResult] == RouteFailure.noRoomRoute.rawValue)
            let (_, none) = walk(RoutingFrame(goals: []), sim, in: vm)
            #expect(none == .returnFalse && sim.personData[PersonData.routeResult] == RouteFailure.noValidGoals.rawValue)
            #expect(sim.position == tile(3, 3), "it didn't move")
        }
    }

    /// A cancelled interaction stops the Sim where it is; a non-interruptable one walks on.
    @Test func cancellingStopsTheWalk() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            sim.thread.stack.removeAll()
            let frame = caller(2, operand: [0, 0, 0, 0, 0, 2, 7, 7], on: sim)
            sim.thread.push(frame)
            sim.thread.pushRoute(RoutingFrame(goals: [RouteGoal(position: tile(3, 2))]), from: frame)
            for _ in 0..<6 { vm.tick() }
            sim.setFlag(EntityFlag.interactionCanceled, true)
            let (_, exit) = run(frame, sim, in: vm)
            #expect(exit == .returnFalse && sim.personData[PersonData.routeResult] == RouteFailure.interrupted.rawValue)
            #expect(sim.position != tile(3, 2) && sim.position != tile(3, 3), "stopped partway")
        }
    }

    @Test func aNonInterruptableSimWalksOn() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            sim.setFlag(EntityFlag.interactionCanceled, true)
            sim.personData[PersonData.nonInterruptable] = 1
            let (_, exit) = walk(RoutingFrame(goals: [RouteGoal(position: tile(3, 2))]), sim, in: vm)
            #expect(exit == .returnTrue && sim.position == tile(3, 2))
        }
    }

    /// Go To Relative Position, anywhere near the ball on 4,3: the Sim walks to a spot a tile or so
    /// from it, facing it.
    @Test func goToRelativePositionWalksBesideTheObject() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
            #expect(try vm.place(ball.group, at: tile(4, 3), facing: .north).status == .success)
            try vm.move(sim, to: tile(2, 2))
            sim.thread.stack.removeAll()
            let operand = Primitives.GotoRelativePosition.Operand(location: -1, direction: -2).encoded()
            let frame = caller(27, operand: operand, on: sim)
            frame.stackObject = ball
            sim.thread.push(frame)
            let (_, exit) = run(frame, sim, in: vm)
            #expect(exit == .returnTrue)
            let distance = sim.position.distance(to: ball.position)
            #expect((14...34).contains(distance), "beside the ball, \(distance) sixteenths away")
            #expect(vm.reportedErrors.isEmpty)
        }
    }

    /// Look Towards' body turn (mode 2) turns the Sim to face the stack object.
    @Test func lookTowardsTurnsTheBody() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
            #expect(try vm.place(ball.group, at: tile(4, 3), facing: .north).status == .success)
            sim.thread.stack.removeAll()
            let frame = caller(22, operand: Primitives.LookTowards.Operand(mode: 2).encoded(), on: sim)
            frame.stackObject = ball
            sim.thread.push(frame)
            let (_, exit) = run(frame, sim, in: vm)
            #expect(exit == .returnTrue && sim.direction == .east && sim.position == tile(3, 3))
        }
    }

    @Test func walkingRepeats() throws {
        var trails: [[LotPosition]] = []
        for _ in 0..<2 {
            try withJoinedSim { (vm: VM, sim: Entity) throws in
                sim.thread.stack.removeAll()
                let frame = caller(2, operand: [0, 0, 0, 0, 0, 2, 7, 7], on: sim)
                sim.thread.push(frame)
                sim.thread.pushRoute(RoutingFrame(goals: [RouteGoal(position: tile(2, 2))]), from: frame)
                var trail: [LotPosition] = []
                for _ in 0..<40 { vm.tick(); trail.append(sim.position) }
                trails.append(trail)
            }
        }
        #expect(trails[0] == trails[1] && trails[0].last == tile(2, 2))
    }

    /// A wall on a tile's top-left edge is a band along it; a door in it leaves it out.
    @Test func wallsBecomeObstacles() throws {
        var architecture = try Architecture(width: 8, height: 8)
        try architecture.setWall(WallTile(segments: [.topLeft]), atX: 2, y: 3, level: 1)
        try architecture.setWall(WallTile(segments: [.topRight]), atX: 5, y: 5, level: 1)
        #expect(try architecture.wallObstacles(level: 1) == [Obstacle(29, 45, 38, 67), Obstacle(77, 77, 99, 86)])
        var door = WallTile(segments: [.topLeft])
        door.topLeftDoor = true
        try architecture.setWall(door, atX: 2, y: 3, level: 1)
        #expect(try architecture.wallObstacles(level: 1) == [Obstacle(77, 77, 99, 86)])
        #expect(throws: SimAnticsError.indexOutOfRange("level 6")) { try architecture.wallObstacles(level: 6) }
    }

    /// The mock lot's closed room has walls; the Sim's route keeps out of them and the objects
    /// that don't let people through, but not its own footprint.
    @Test func aSimsObstaclesAreTheWallsAndWhatBlocksIt() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let walls = try vm.architecture.wallObstacles(level: 1)
            let obstacles = try vm.routeObstacles(level: 1, for: sim)
            #expect(!walls.isEmpty && obstacles.starts(with: walls))
            if let own = sim.footprint { #expect(!obstacles.dropFirst(walls.count).contains(own)) }
            #expect(throws: SimAnticsError.self) { try vm.routeObstacles(level: 0, for: sim) }
        }
    }
}
