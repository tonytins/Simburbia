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

    /// A route with nowhere to go returns false to the routine that pushed it, with "no valid
    /// goals" in the Sim's `PrimitiveResult`.
    @Test func aRouteWithNoGoalsFailsAndSaysWhy() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            sim.thread.stack.removeAll()
            let caller = StackFrame(thread: sim.thread, routine: Routine(id: 4096, instructions: [
                Instruction(index: 0, opcode: 2, truePointer: 254, falsePointer: 255,
                            operand: PrimitiveTable.standard.decode(opcode: 2, operand: [0, 0, 0, 0, 0, 2, 7, 7])),
            ]), caller: sim, callee: sim, codeOwner: sim.object)
            sim.thread.push(caller)
            sim.thread.pushRoute(RoutingFrame(goals: []), from: caller)
            #expect(sim.thread.stack.last?.routine.name == "routing")
            vm.tick()
            #expect(try sim.value(of: ObjectVariable.primitiveResult.rawValue) == RouteFailure.noValidGoals.rawValue)
            #expect(sim.thread.stack.allSatisfy { $0.route == nil })
            #expect(vm.reportedErrors.isEmpty)
        }
    }

    @Test func walkingWaitsForItsPhase() throws {
        try withJoinedSim { (vm: VM, sim: Entity) throws in
            let route = RoutingFrame(goals: [RouteGoal(position: .center(ofTileX: 4, y: 3, level: 1))])
            #expect(throws: SimAnticsError.unsupported("walking a route (phase E4)")) { try route.step(for: sim) }
        }
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
