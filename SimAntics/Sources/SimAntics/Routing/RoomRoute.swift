extension Entity {
    /// Whether the object is a portal: something a route passes through between rooms, a door or
    /// stairs, with a routine at its portal entry point (15).
    var isPortal: Bool {
        guard let table = entryPoints, table.count > EntryPointIndex.portal.rawValue else { return false }
        return table[EntryPointIndex.portal.rawValue].actionFunction != 0
    }
}

extension VM {
    /// The room a portal leads to: the room of another part of its object that's a portal too and
    /// stands in a different room, such as a door's other half or the other end of stairs; `nil`
    /// for a portal with no such part.
    func room(beyond portal: Entity) -> UInt16? {
        let here = architecture.room(at: portal.position)
        for part in portal.group.objects where part !== portal && part.isPortal {
            let there = architecture.room(at: part.position)
            if there != here { return there }
        }
        return nil
    }

    /// The portals a Sim at `position` passes through, in order, to reach `room`; `nil` when no
    /// chain of portals reaches it, and empty when it's there already.
    ///
    /// The shortest chain by walking distance between portals (in sixteenths, each level between
    /// counting 10 tiles), found from the Sim's position through each room's portals, leaving out
    /// the portals in `avoiding`. Equal distances go to the portal with the lowest object ID, so a
    /// lot routes through the same doors on every machine.
    public func roomRoute(from position: LotPosition, to room: UInt16, avoiding: [Int16] = []) -> [Entity]? {
        let here = architecture.room(at: position)
        if here == room { return [] }
        // Every portal that leads somewhere, with the room it's in and the room it leads to.
        let portals = entities.compactMap { entity -> (portal: Entity, from: UInt16, to: UInt16)? in
            guard entity.isPortal, !avoiding.contains(entity.objectID), !entity.position.isOutOfWorld,
                  let beyond = self.room(beyond: entity) else { return nil }
            return (entity, architecture.room(at: entity.position), beyond)
        }
        func distance(_ a: LotPosition, _ b: LotPosition) -> Int {
            a.distance(to: b) + abs(Int(a.level) - Int(b.level)) * 160
        }

        // Dijkstra over portals, the Sim's position the start.
        var best: [Int: Int] = [:]          // portal index → cost
        var previous: [Int: Int] = [:]      // portal index → the portal before it, if any
        var done = Set<Int>()
        var frontier: [(cost: Int, index: Int)] = []
        for (index, entry) in portals.enumerated() where entry.from == here {
            let cost = distance(position, entry.portal.position)
            best[index] = cost
            frontier.append((cost, index))
        }
        while !frontier.isEmpty {
            // The cheapest, and among equals the lowest object ID.
            let pick = frontier.indices.min { a, b in
                let x = frontier[a], y = frontier[b]
                return x.cost != y.cost ? x.cost < y.cost : portals[x.index].portal.objectID < portals[y.index].portal.objectID
            } ?? 0
            let (cost, index) = frontier.remove(at: pick)
            guard !done.contains(index), best[index] == cost else { continue }
            done.insert(index)
            let entry = portals[index]
            if entry.to == room {
                var chain = [index]
                while let before = previous[chain[0]] { chain.insert(before, at: 0) }
                return chain.map { portals[$0].portal }
            }
            for (next, candidate) in portals.enumerated() where candidate.from == entry.to && !done.contains(next) {
                let through = cost + distance(entry.portal.position, candidate.portal.position)
                if let known = best[next], known <= through { continue }
                best[next] = through
                previous[next] = index
                frontier.append((through, next))
            }
        }
        return nil
    }
}
