import Foundation
import Testing
import TSOContent
@testable import SimAntics

/// Routes between rooms (phase E5), on `mock-lot-sim.xml`: a closed room of tiles 2 to 4, with the
/// chair on 4,4 and the mock Sim joined on 3,3. The mock install has no doors, so a mock table
/// stands in for one: its two parts get a portal routine (entry point 15), one part inside the
/// room and the other outside.
@Suite struct PortalTests {
    private func withRoom(_ body: (VM, Entity) throws -> Void) throws {
        let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
        let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
        try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
        let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Walker", persistID: 9, bodyOutfit: 0)))
        try withExtendedLifetime(vm) { try body(vm, sim) }
    }

    private func tile(_ x: Int16, _ y: Int16) -> LotPosition { .center(ofTileX: x, y: y, level: 1) }

    /// The mock table as a door: its parts on `inside` and `outside`, each with the global's
    /// routine 256 (which returns true and moves nobody) as its portal routine.
    private func door(in vm: VM, inside: LotPosition, outside: LotPosition) throws -> (inside: Entity, outside: Entity) {
        let group = try #require(try vm.createObject(guid: mockTableGUID))
        #expect(group.objects.count == 2)
        let parts = (group.objects[0], group.objects[1])
        for (part, position) in [(parts.0, inside), (parts.1, outside)] {
            var table = part.entryPoints ?? []
            while table.count <= Entity.EntryPointIndex.portal.rawValue { table.append(.init(conditionFunction: 0, actionFunction: 0)) }
            table[Entity.EntryPointIndex.portal.rawValue] = .init(conditionFunction: 0, actionFunction: 256)
            part.entryPoints = table
            part.position = position
        }
        return parts
    }

    private func walk(_ route: RoutingFrame, _ sim: Entity, in vm: VM, limit: Int = 600) -> (ticks: Int, exit: ExitCode?) {
        sim.thread.stack.removeAll()
        let frame = StackFrame(thread: sim.thread, routine: Routine(id: 4096, instructions: [
            Instruction(index: 0, opcode: 2, truePointer: 254, falsePointer: 255,
                        operand: PrimitiveTable.standard.decode(opcode: 2, operand: [0, 0, 0, 0, 0, 2, 7, 7])),
        ]), caller: sim, callee: sim, codeOwner: sim.object)
        sim.thread.push(frame)
        sim.thread.pushRoute(route, from: frame)
        for tick in 1...limit {
            vm.tick()
            if !sim.thread.stack.contains(where: { $0 === frame }) { return (tick, sim.thread.lastExitCode) }
        }
        return (limit, nil)
    }

    @Test func aRoomRouteGoesThroughThePortalBetween() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let outside = vm.architecture.room(at: tile(7, 7))
            #expect(vm.roomRoute(from: sim.position, to: outside) == nil, "no doors yet")
            let door = try door(in: vm, inside: tile(3, 2), outside: tile(7, 7))
            #expect(door.inside.isPortal && vm.room(beyond: door.inside) == outside)
            #expect(vm.roomRoute(from: sim.position, to: outside)?.map(\.objectID) == [door.inside.objectID])
            #expect(vm.roomRoute(from: sim.position, to: outside, avoiding: [door.inside.objectID]) == nil)
            #expect(vm.roomRoute(from: sim.position, to: vm.architecture.room(at: sim.position))?.isEmpty == true)
        }
    }

    /// The portal's routine returns true but leaves the Sim where it was: the route leaves that
    /// portal out, finds no other, and fails with "no room route" instead of trying it for ever.
    @Test func aPortalThatDoesntTakeTheSimThroughIsLeftOut() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            _ = try door(in: vm, inside: tile(3, 2), outside: tile(7, 7))
            let start = sim.position
            let (ticks, exit) = walk(RoutingFrame(goals: [RouteGoal(position: tile(7, 7))]), sim, in: vm)
            #expect(exit == .returnFalse && ticks < 10)
            #expect(sim.personData[PersonData.routeResult] == RouteFailure.noRoomRoute.rawValue)
            #expect(sim.position == start)
        }
    }

    /// A slot that ignores rooms (a door's other side) may route out of the room: the closed room
    /// has no way out, so it's "no path" rather than "no room route".
    @Test func ignoringRoomsLeavesTheRoom() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let goal = [RouteGoal(position: tile(7, 7))]
            #expect(try vm.findPath(for: sim, from: sim.position, to: goal) == .failure(.noRoomRoute))
            #expect(try vm.findPath(for: sim, from: sim.position, to: goal, ignoringRooms: true) == .failure(.noPath))
        }
    }

    /// A Sim standing inside a chair's footprint, as one does after sitting, walks out of it.
    /// Before E5 every step out collided with the chair, and the route failed with "no path".
    @Test func aSimStepsOutOfWhatItStandsIn() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let chair = try #require(try vm.createObject(guid: mockChairGUID)?.objects.first)
            #expect(try vm.place(chair.group, at: sim.position, facing: .north, flags: .allowIntersection).status == .success)
            #expect(chair.footprint?.intersects(try #require(sim.footprint)) == true)
            let (_, exit) = walk(RoutingFrame(goals: [RouteGoal(position: tile(3, 2))]), sim, in: vm)
            #expect(exit == .returnTrue)
            #expect(sim.position == tile(3, 2))
        }
    }

    /// The mock install has no shoo object, so nobody is asked to move; nor is the asker itself.
    @Test func withoutTheShooObjectNobodyIsAsked() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let other = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Blocker", persistID: 10, bodyOutfit: 0)))
            #expect(try !vm.shoo(other, by: sim))
            #expect(try !vm.shoo(sim, by: sim))
            #expect(other.thread.queue.allSatisfy { $0.callee?.object.guid != VM.shooObjectGUID })
        }
    }
}
