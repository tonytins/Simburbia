import TSOFiles

/// A place a Sim may stand or sit to use an object, found from one of its routing slots.
public struct RouteSpot {
    public var position: LotPosition
    /// Which way the Sim faces there, in radians clockwise from north (-π to π); `nil` when the
    /// slot lets it face anywhere.
    public var facing: Double?
    /// Higher is better.
    public var score: Double
    /// The chair the Sim sits in there, for a slot that sits.
    public var chair: Entity?
    /// Which of the slot's directions the spot is in, as the slot's direction bits.
    public var directions: SLOT.Flags
}

/// The spots a routing slot offers, best first, or why it offers none.
public struct SlotSearch {
    public var spots: [RouteSpot]
    /// Why there are no spots: no valid goals, a wall in the way, no chair, or the tile taken;
    /// `nil` when there are spots.
    public var failure: RouteFailure?
    /// What took the tile, for a taken tile.
    public var blocker: Entity?
}

extension Entity {
    /// The object's routing slots (`SLOT` slots of type 3), in file order.
    func routingSlots() throws(SimAnticsError) -> [SLOT.Slot] {
        do {
            return try object.resource.chunk(SLOT.self, id: object.definition.slotID)?.slots(ofType: 3) ?? []
        } catch {
            throw .simantics("SLOT \(object.definition.slotID) doesn't parse: \(error)")
        }
    }

    /// The facing in radians clockwise from north.
    var radians: Double { Double(direction.notch) * DeterministicMath.quarterPi }
}

extension VM {
    /// The global's routing slots (`SLOT` 100's slots of type 3), which Snap's mode 4 numbers.
    func globalRoutingSlots() throws(SimAnticsError) -> [SLOT.Slot] {
        do {
            return try global.chunk(SLOT.self, id: 100)?.slots(ofType: 3) ?? []
        } catch {
            throw .simantics("the global's SLOT 100 doesn't parse: \(error)")
        }
    }

    /// The most grid points a slot's search may try, so a slot with a huge reach can't stall a tick.
    static let maximumSlotSearchPoints = 40_000

    /// The spots around `object` where `sim` may stand or sit for a routing slot, best first.
    ///
    /// The slot is measured from the object's position (or the middle of its parts, with "use
    /// average object location"), plus the slot's offset turned with the object.
    ///
    /// - **Snap to direction:** one spot there, facing the slot's direction turned with the object.
    /// - **An offset, or no directions:** one spot there, facing as the slot says.
    /// - **Otherwise** the points around it, at the slot's proximity: eight around a circle when
    ///   its least and most proximity are the same, else a grid at its resolution within them. A
    ///   point counts when it's in one of the slot's directions from the object (turned with it)
    ///   and, unless the slot ignores rooms, in the object's room. It scores higher the nearer its
    ///   distance is to the slot's optimal proximity; a slot with "random scoring" adds a random
    ///   fraction, from the VM's seed.
    ///
    /// Each spot must be on the lot, have no wall between it and the object, and fit the Sim. A
    /// game object in the way is a chair the Sim sits in, for a slot that sits and an object with a
    /// sit entry point facing within 45° of the spot's facing, or else takes the tile. Another Sim,
    /// or a door, there makes the spot a last resort. A spot then loses a third of its distance from
    /// the Sim, and is weighted by the slot's standing or sitting preference.
    ///
    /// - Throws: ``SimAnticsError/simantics(_:)`` if the slot would search more than
    ///   ``maximumSlotSearchPoints`` points; errors from an object's code asked about the spot.
    public func findSpots(for slot: SLOT.Slot, around object: Entity, for sim: Entity) throws(SimAnticsError) -> SlotSearch {
        var search = SlotSearchState(slot: slot)
        let level = object.position.level

        // The middle, in tiles.
        var center = (x: Double(object.position.x) / 16, y: Double(object.position.y) / 16)
        let parts = object.group.objects
        if slot.flags.contains(.useAverageObjectLocation), object.group.isMultiTile, !parts.isEmpty {
            center = (parts.reduce(0.0) { $0 + Double($1.position.x) / 16 } / Double(parts.count),
                      parts.reduce(0.0) { $0 + Double($1.position.y) / 16 } / Double(parts.count))
        }
        let angle = object.radians
        let cosine = DeterministicMath.cos(angle), sine = DeterministicMath.sin(angle)
        let offsetX = Double(slot.offset.x), offsetY = Double(slot.offset.y)
        let point = (x: center.x + (offsetX * cosine - offsetY * sine) / 16,
                     y: center.y + (offsetX * sine + offsetY * cosine) / 16)
        let room = architecture.room(at: object.position)
        let directionBits = slot.flags.rawValue & 255

        if slot.flags.contains(.snapToDirection) {
            var bits = directionBits
            if slot.facing > SLOT.Facing.awayFromObject {
                bits |= Int32(1) << Int32(slot.facing & 7)
            } else if bits == 0 {
                bits = SLOT.Flags.north.rawValue
            }
            let facing = Self.normalized(angle + Double(Self.roundedLog2(bits)) * DeterministicMath.quarterPi)
            try search.add(point, from: object, for: sim, level: level, score: .greatestFiniteMagnitude, facing: facing,
                           directions: SLOT.Flags(rawValue: bits), in: self)
            return search.result
        }
        if directionBits == 0 || slot.offset != .zero {
            try search.add(point, from: object, for: sim, level: level, score: .greatestFiniteMagnitude, facing: nil,
                           directions: slot.flags, in: self)
            return search.result
        }

        let minimum = Int(slot.minProximity), maximum = search.maximumProximity, optimal = search.optimalProximity
        let maxScore = Double(max(optimal - minimum, maximum - optimal))
            + Double(object.position.distance(to: sim.position) + maximum) / 3 + 2
        let ignoresRooms = slot.flags.contains(.ignoreRooms)
        for (dx, dy, distance) in try Self.searchPoints(for: slot, maximum: maximum) {
            guard distance >= Double(minimum) - 0.5, distance <= Double(maximum) + 0.5 else { continue }
            let candidate = (x: point.x + Double(dx) / 16, y: point.y + Double(dy) / 16)
            if !ignoresRooms {
                let at = LotPosition(x: Self.sixteenths(candidate.x), y: Self.sixteenths(candidate.y), level: level)
                guard architecture.room(at: at) == room else { continue }
            }
            let directions = Self.searchDirection(from: point, to: candidate, turnedBy: angle).intersection(slot.flags)
            guard directions.rawValue & 255 != 0 else { continue }
            var score = maxScore - abs(Double(optimal) - distance)
            if slot.flags.contains(.randomScoring) { score += Double(random.next(below: 1024)) / 1024 }
            try search.add(candidate, from: object, for: sim, level: level, score: score, facing: nil, directions: directions, in: self)
        }
        return search.result
    }

    // MARK: Helpers

    /// The points a slot's search tries, as offsets in sixteenths and their distance.
    private static func searchPoints(for slot: SLOT.Slot, maximum: Int) throws(SimAnticsError) -> [(Int, Int, Double)] {
        let minimum = Int(slot.minProximity)
        if maximum == minimum {
            // A circle: the eight compass points.
            return (0..<8).map { i in
                let angle = Double(i) * DeterministicMath.quarterPi
                return (Int((DeterministicMath.sin(angle) * Double(minimum)).rounded()),
                        Int((DeterministicMath.cos(angle) * Double(minimum)).rounded()), Double(minimum))
            }
        }
        let resolution = Int(slot.resolution)
        guard resolution > 0 else { return [] }
        let bound = (maximum / resolution) * resolution
        let side = 2 * (bound / resolution) + 1
        guard side <= Int(Double(maximumSlotSearchPoints).squareRoot()) else {
            throw .simantics("a routing slot would search \(side * side) points")
        }
        var points: [(Int, Int, Double)] = []
        for x in stride(from: -bound, through: bound, by: resolution) {
            for y in stride(from: -bound, through: bound, by: resolution) {
                points.append((x, y, Double(x * x + y * y).squareRoot()))
            }
        }
        return points
    }

    /// Which of the eight directions `to` is from `from`, tile to tile, with the object's facing
    /// taken off: each covers 90°, so a point between two counts as both, less 0.1° at each edge.
    static func searchDirection(from: (x: Double, y: Double), to: (x: Double, y: Double), turnedBy angle: Double) -> SLOT.Flags {
        let dx = to.x.rounded(.down) - from.x.rounded(.down), dy = from.y.rounded(.down) - to.y.rounded(.down)
        let degrees = normalizedDegrees(DeterministicMath.atan2(dx, dy) * 180 / DeterministicMath.pi - angle * 180 / DeterministicMath.pi)
        let edge = 0.1
        var result: SLOT.Flags = []
        if degrees >= -45 + edge && degrees <= 45 - edge { result.insert(.north) }
        if degrees >= 0 + edge && degrees <= 90 - edge { result.insert(.northEast) }
        if degrees >= 45 + edge && degrees <= 135 - edge { result.insert(.east) }
        if (degrees >= 90 + edge && degrees <= 180 - edge) || degrees <= -180 - edge { result.insert(.southEast) }
        if degrees >= 135 + edge || degrees <= -135 - edge { result.insert(.south) }
        if (degrees >= -180 + edge && degrees <= -90 - edge) || degrees >= 180 + edge { result.insert(.southWest) }
        if degrees >= -135 + edge && degrees <= -45 - edge { result.insert(.west) }
        if degrees >= -90 + edge && degrees <= 0 - edge { result.insert(.northWest) }
        return result
    }

    /// An angle in radians brought within -π to π.
    static func normalized(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: 2 * DeterministicMath.pi)
        if result > DeterministicMath.pi { result -= 2 * DeterministicMath.pi }
        if result <= -DeterministicMath.pi { result += 2 * DeterministicMath.pi }
        return result
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        var result = degrees.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result <= -180 { result += 360 }
        return result
    }

    /// The nearest whole power of two's exponent for direction bits (1 to 255), in integers.
    static func roundedLog2(_ bits: Int32) -> Int {
        let value = Int(bits & 255)
        guard value > 0 else { return 0 }
        // log2(v) rounds to k when 2^(2k - 1) <= v² < 2^(2k + 1).
        var k = 0
        while value * value >= 1 << (2 * k + 1) { k += 1 }
        return k
    }

    /// A position in tiles, rounded to sixteenths and kept within a lot's reach.
    static func sixteenths(_ tiles: Double) -> Int16 {
        let value = (tiles * 16).rounded()
        guard value.isFinite else { return Int16.min }
        return Int16(max(min(value, Double(Int16.max)), Double(Int16.min)))
    }
}

/// A search for spots in progress: what's found, and the worst reason a candidate was turned down.
private struct SlotSearchState {
    let slot: SLOT.Slot
    var spots: [RouteSpot] = []
    var failure: RouteFailure
    var blocker: Entity?

    /// How much a reason for no spots outweighs another, least first.
    private static let failureOrder: [RouteFailure] = [.noValidGoals, .wallInWay, .noChair, .destinationTileOccupiedByPerson,
                                                       .destinationTileOccupied]

    init(slot: SLOT.Slot) {
        self.slot = slot
        failure = slot.sitting > 0 && slot.standing == 0 ? .noChair : .noValidGoals
    }

    private var onlySits: Bool { slot.sitting > 0 && slot.standing == 0 }
    var maximumProximity: Int { slot.maxProximity == 0 ? Int(slot.minProximity) : Int(slot.maxProximity) }
    var optimalProximity: Int { slot.optimalProximity == 0 ? Int(slot.minProximity) : Int(slot.optimalProximity) }

    var result: SlotSearch {
        // Highest score first; equal scores keep the order they were found in.
        let ordered = spots.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }.map(\.element)
        return SlotSearch(spots: ordered, failure: ordered.isEmpty ? failure : nil, blocker: ordered.isEmpty ? blocker : nil)
    }

    private mutating func fail(_ reason: RouteFailure, _ entity: Entity?) {
        let order = Self.failureOrder
        if (order.firstIndex(of: reason) ?? -1) > (order.firstIndex(of: failure) ?? -1) {
            failure = reason
            blocker = entity
        }
    }

    /// Checks a candidate and adds it as a spot if it's usable.
    mutating func add(_ point: (x: Double, y: Double), from object: Entity, for sim: Entity, level: Int8, score: Double,
                      facing given: Double?, directions: SLOT.Flags, in vm: VM) throws(SimAnticsError) {
        let position = LotPosition(x: VM.sixteenths(point.x), y: VM.sixteenths(point.y), level: level)
        guard !vm.architecture.isOutOfBounds(position) else { return }
        var score = score - Double(position.distance(to: sim.position)) / 3
        let snaps = slot.snapTargetSlot >= 0
        if !snaps, try vm.architecture.wallBetween(tileX: Int(point.x.rounded(.towardZero)), y: Int(point.y.rounded(.towardZero)),
                                                 andTileX: Int(object.position.tileX), y: Int(object.position.tileY), level: Int(level)) {
            fail(.wallInWay, nil)
            return
        }

        var facing = given
        if given == nil {
            let objectPoint = (x: Double(object.position.x) / 16, y: Double(object.position.y) / 16)
            switch slot.facing {
            case SLOT.Facing.towardsObject:
                facing = DeterministicMath.atan2(objectPoint.x - point.x, -(objectPoint.y - point.y))
            case SLOT.Facing.awayFromObject:
                facing = DeterministicMath.atan2(point.x - objectPoint.x, -(point.y - objectPoint.y))
            case SLOT.Facing.anywhere:
                facing = nil
            default:
                let notch = (Int(slot.facing) + object.direction.notch) % 8
                facing = VM.normalized(Double((notch + 8) % 8) * DeterministicMath.quarterPi)
            }
        }

        var chair: Entity?
        var lastResort = false
        if !snaps {
            let fit = try sim.placement(at: position, facing: .north, flags: .acceptSlots)
            if fit.status != .success, let inWay = fit.object {
                if inWay.isAvatar {
                    lastResort = true
                } else if slot.sitting > 0, let table = inWay.entryPoints, table.count > 26, table[26].actionFunction != 0 {
                    chair = inWay
                } else {
                    fail(.destinationTileOccupied, inWay)
                    return
                }
            }
            if vm.objects(at: position)?.contains(where: { $0.hasFlag2(EntityFlag.architecturalDoor) }) == true { lastResort = true }
            if let chair, let wanted = facing, abs(VM.normalized(chair.radians - wanted)) > DeterministicMath.quarterPi { return }
            if chair == nil && onlySits { return }
            score *= Double(chair != nil ? slot.sitting : slot.standing)
            if lastResort { score = max(Double.leastNonzeroMagnitude, score) }
        }
        spots.append(RouteSpot(position: position, facing: facing, score: score, chair: chair, directions: directions))
    }
}
