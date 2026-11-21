import Foundation
import Testing
import TSOContent
import TSOFiles
@testable import SimAntics

/// Routing slots read into spots, on `mock-lot-sim.xml`: a closed room of tiles 2 to 4, with the
/// lamp on 4,2, the register on 2,4, the chair on 4,4, and the mock Sim joined on 3,3 facing north.
@Suite struct RouteSlotTests {
    private func withRoom(_ body: (VM, Entity) throws -> Void) throws {
        let vm = try VM(content: try GameContent(.init(gameDirectory: mockInstall)), seed: 1)
        let file = mockInstall.deletingLastPathComponent().appendingPathComponent("Lots/mock-lot-sim.xml")
        try vm.load(try Blueprint(xml: try Data(contentsOf: file)))
        let sim = try #require(try vm.joinSim(template: mockSimGUID, identity: SimIdentity(name: "Walker", persistID: 9, bodyOutfit: 0)))
        try withExtendedLifetime(vm) { try body(vm, sim) }
    }

    private func tile(_ x: Int16, _ y: Int16) -> LotPosition { .center(ofTileX: x, y: y, level: 1) }

    private static let everyDirection = SLOT.Flags(rawValue: 255)

    /// A circle of one tile around the ball on 4,3: north is the lamp, south the chair, east is
    /// outside the room; west (where the Sim stands, nearest it), north-west, and south-west are
    /// free. Each faces the ball.
    @Test func aCircleSlotFindsTheFreeSpotsInTheRoom() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
            #expect(try vm.place(ball.group, at: tile(4, 3), facing: .north).status == .success)
            let slot = SLOT.Slot(type: 3, flags: Self.everyDirection, minProximity: 16)
            let search = try vm.findSpots(for: slot, around: ball, for: sim)
            #expect(search.failure == nil)
            #expect(search.spots.first?.position == tile(3, 3), "the nearest to the Sim first")
            #expect(search.spots.map(\.position.tileX).allSatisfy { $0 == 3 }, "only the west side is free")
            #expect(search.spots.count == 3)
            #expect(search.spots.first?.facing == DeterministicMath.halfPi, "facing the ball, east")
        }
    }

    /// The ball just outside the room's east wall, on 5,3, and a slot a tile west of it: inside the
    /// room, but with the wall between.
    @Test func aWallBetweenTurnsASpotDown() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
            let placed = try vm.place(ball.group, at: tile(5, 3), facing: .north)
            #expect(placed.status == .success, "\(placed.status) \(placed.object?.object.guid ?? 0)")
            let slot = SLOT.Slot(type: 3, offset: SIMD3(-16, 0, 0))
            let search = try vm.findSpots(for: slot, around: ball, for: sim)
            #expect(search.spots.isEmpty && search.failure == .wallInWay)
        }
    }

    /// Snapping to a direction: one spot at the object, facing the slot's way turned with it.
    @Test func aSlotThatSnapsToADirectionFacesIt() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            sim.direction = .east
            let slot = SLOT.Slot(type: 3, flags: .snapToDirection, facing: 2)
            let search = try vm.findSpots(for: slot, around: sim, for: sim)
            #expect(search.spots.map(\.position) == [sim.position])
            #expect(search.spots.first?.facing == DeterministicMath.pi, "east, turned a quarter more: south")
        }
    }

    @Test func aSlotThatOnlySitsNeedsAChair() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let ball = try #require(try vm.createObject(guid: mockBallGUID)?.objects.first)
            #expect(try vm.place(ball.group, at: tile(4, 3), facing: .north).status == .success)
            let slot = SLOT.Slot(type: 3, standing: 0, sitting: 1, flags: Self.everyDirection, minProximity: 16)
            let search = try vm.findSpots(for: slot, around: ball, for: sim)
            #expect(search.spots.isEmpty)
            #expect(search.failure == .destinationTileOccupied || search.failure == .noChair)
        }
    }

    @Test func aHugeSearchIsAnErrorNotAStall() throws {
        try withRoom { (vm: VM, sim: Entity) throws in
            let slot = SLOT.Slot(type: 3, flags: Self.everyDirection, minProximity: 0, maxProximity: 30_000, resolution: 1)
            #expect(throws: SimAnticsError.self) { try vm.findSpots(for: slot, around: sim, for: sim) }
            let none = SLOT.Slot(type: 3, flags: Self.everyDirection, minProximity: 0, maxProximity: 32, resolution: 0)
            #expect(try vm.findSpots(for: none, around: sim, for: sim).failure == .noValidGoals, "no resolution, no points")
        }
    }

    @Test func directionsAndExponents() {
        #expect(VM.searchDirection(from: (0.5, 0.5), to: (0.5, -0.5), turnedBy: 0) == [.north])
        #expect(VM.searchDirection(from: (0.5, 0.5), to: (1.5, -0.5), turnedBy: 0) == [.northEast])
        #expect(VM.searchDirection(from: (0.5, 0.5), to: (1.5, 0.5), turnedBy: DeterministicMath.halfPi) == [.north],
                "east of an object facing east is its north")
        #expect([1, 2, 3, 4, 5, 6, 128, 255].map { VM.roundedLog2(Int32($0)) } == [0, 1, 2, 2, 2, 3, 7, 8])
    }

    /// A wall on tile 3,2's top-left edge stands between 2,2 and 4,2, but not along column 2; a
    /// door in it lets the line through.
    @Test func wallsBetweenTiles() throws {
        var architecture = try Architecture(width: 8, height: 8)
        try architecture.setWall(WallTile(segments: [.topLeft]), atX: 3, y: 2, level: 1)
        #expect(try architecture.wallBetween(tileX: 2, y: 2, andTileX: 4, y: 2, level: 1))
        #expect(try architecture.wallBetween(tileX: 4, y: 2, andTileX: 2, y: 2, level: 1))
        #expect(try !architecture.wallBetween(tileX: 2, y: 2, andTileX: 2, y: 5, level: 1))
        var door = WallTile(segments: [.topLeft])
        door.topLeftDoor = true
        try architecture.setWall(door, atX: 3, y: 2, level: 1)
        #expect(try !architecture.wallBetween(tileX: 2, y: 2, andTileX: 4, y: 2, level: 1))
    }

    /// An object's routing slots come from its `SLOT`, those of type 3 only.
    @Test func routingSlotsAreTheSlotsOfTypeThree() throws {
        var writer = ByteWriter()
        writer.uint32(0); writer.uint32(10); writer.ascii("TOLS"); writer.uint32(2)
        for type: UInt16 in [0, 3] {
            writer.uint16(type)
            for value: Float in [0, 0, 0] { writer.uint32(value.bitPattern) }
            for value: Int32 in [1, 0, 0, 255, -1, 16, 16, 16, 0, 0] { writer.int32(value) }
            writer.uint32(Float(0).bitPattern)
            writer.int32(0); writer.int32(-2); writer.int32(16)
        }
        try withVM(chair: [ChunkFixture(type: "SLOT", id: 128, contents: writer.bytes)], chairWords: [18: 128]) { _, chair in
            let slots = try chair.routingSlots()
            #expect(slots.count == 1 && slots[0].type == 3 && slots[0].minProximity == 16)
        }
    }
}
