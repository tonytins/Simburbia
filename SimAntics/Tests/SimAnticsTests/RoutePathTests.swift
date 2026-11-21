import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// Paths within a room, on `mock-lot-sim.xml`: a closed room of tiles 2 to 4, with the lamp on
/// 4,2, the register on 2,4, the chair on 4,4, and the mock Sim joined on 3,3.
@Suite struct RoutePathTests {
    private func withRoom(_ body: (VM, Entity) throws -> Void) throws {
        let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
        let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
        try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
        let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Walker", persistID: 9, bodyOutfit: 0)))
        try withExtendedLifetime(vm) { try body(vm, sim) }
    }

    private func tile(_ x: Int16, _ y: Int16) -> LotPosition { .center(ofTileX: x, y: y, level: 1) }

    @Test func aClearWayIsOneStraightLine() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let path = try vm.findPath(for: sim, from: sim.position, to: [RouteGoal(position: tile(3, 2))]).get()
            #expect(path.waypoints == [tile(3, 3), tile(3, 2)] && path.goal == 0)
        }
    }

    /// With the Sim on 2,3, a second chair on 3,3, and the lamp taken away, the way to 4,3 bends
    /// around the chair through the north side, and every turn stays clear of it. (With the lamp,
    /// the gaps are narrower than a Sim, and there's no way at all.)
    @Test func aPathGoesAroundWhatsInTheWay() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            try vm.move(sim, to: tile(2, 3))
            let lamp = try #require(vm.entities.first { $0.object.guid == mockLampGUID })
            #expect(try vm.findPath(for: sim, from: sim.position, to: [RouteGoal(position: tile(4, 3))]) != .failure(.noPath))
            try vm.delete(lamp)
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(try vm.place(chair.group, at: tile(3, 3), facing: .north).status == .success)
            let footprint = try #require(chair.footprint)
            let path = try vm.findPath(for: sim, from: sim.position, to: [RouteGoal(position: tile(4, 3))]).get()
            #expect(path.waypoints.first == tile(2, 3) && path.waypoints.last == tile(4, 3))
            #expect(path.waypoints.count > 2, "it can't go straight through")
            for point in path.waypoints {
                #expect(!Obstacle(footprint.x1 - 3, footprint.y1 - 3, footprint.x2 + 3, footprint.y2 + 3).strictlyContains(point))
            }
        }
    }

    @Test func theNearestOfSeveralGoalsWins() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let goals = [RouteGoal(position: tile(2, 2)), RouteGoal(position: tile(3, 4))]
            let path = try vm.findPath(for: sim, from: sim.position, to: goals).get()
            #expect(path.goal == 1 && path.waypoints.last == tile(3, 4))
        }
    }

    @Test func aGoalInAnotherRoomWaitsForDoors() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            #expect(try vm.findPath(for: sim, from: sim.position, to: [RouteGoal(position: tile(7, 7))]) == .failure(.noRoomRoute))
            #expect(try vm.findPath(for: sim, from: sim.position, to: []) == .failure(.noValidGoals))
        }
    }

    /// A Sim standing inside something, as at a chair, can still walk away.
    @Test func aSimInsideSomethingCanStepOut() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let chair = try #require(vm.entities.first { $0.object.guid == mockChairGUID && $0.position == tile(4, 4) })
            let path = try vm.findPath(for: sim, from: chair.position, to: [RouteGoal(position: tile(3, 3))]).get()
            #expect(path.waypoints.last == tile(3, 3))
        }
    }

    @Test func aSearchStopsAtItsLimit() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            var grid = RouteGrid(architecture: vm.architecture, level: 1, room: vm.architecture.room(at: sim.position), obstacles: [])
            #expect(grid.search(from: Cell(tile(2, 2)), to: [Cell(tile(4, 4))], limit: 10) == nil)
            #expect(grid.search(from: Cell(tile(2, 2)), to: [Cell(tile(4, 4))], limit: 10_000) != nil)
        }
    }

    @Test func theSameLotAlwaysRoutesTheSameWay() throws {
        var paths: [RoutePath] = []
        for _ in 0..<2 {
            try withRoom { (vm: VM, sim: Entity) throws in
                try vm.move(sim, to: tile(2, 2))
                paths.append(try vm.findPath(for: sim, from: sim.position, to: [RouteGoal(position: tile(4, 3))]).get())
            }
        }
        #expect(paths[0] == paths[1])
    }
}
