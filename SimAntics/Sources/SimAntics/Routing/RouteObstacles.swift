extension Architecture {
    /// A level's walls as rectangles a route keeps out of, in sixteenths of a tile, tile by tile
    /// (`WallObs`). A straight wall is a band 9 wide along its tile's edge, 3 out and 6 in, and
    /// runs 3 past each end; a door in it leaves it out. A diagonal is four small squares along
    /// it.
    ///
    /// - Throws: ``SimAnticsError/indexOutOfRange(_:)`` for a level past the lot's stories.
    public func wallObstacles(level: Int) throws(SimAnticsError) -> [Obstacle] {
        guard (1...Self.stories).contains(level) else { throw .indexOutOfRange("level \(level)") }
        var obstacles: [Obstacle] = []
        for y in 0..<height {
            for x in 0..<width {
                let wall = walls[level - 1][y * width + x]
                let segments = wall.segments
                guard segments.rawValue != 0 else { continue }
                let ox = x << 4, oy = y << 4
                if segments.contains(.horizontalDiagonal) {
                    obstacles += [Obstacle(ox + 11, oy - 1, ox + 17, oy + 5), Obstacle(ox + 7, oy + 3, ox + 13, oy + 9),
                                  Obstacle(ox + 3, oy + 7, ox + 9, oy + 13), Obstacle(ox - 1, oy + 11, ox + 5, oy + 17)]
                }
                if segments.contains(.verticalDiagonal) {
                    obstacles += [Obstacle(ox - 1, oy - 1, ox + 5, oy + 5), Obstacle(ox + 3, oy + 3, ox + 9, oy + 9),
                                  Obstacle(ox + 7, oy + 7, ox + 13, oy + 13), Obstacle(ox + 11, oy + 11, ox + 17, oy + 17)]
                }
                if segments.contains(.topLeft) && !wall.topLeftDoor {
                    obstacles.append(Obstacle(ox - 3, oy - 3, ox + 6, oy + 19))
                }
                if segments.contains(.topRight) && !wall.topRightDoor {
                    obstacles.append(Obstacle(ox - 3, oy - 3, ox + 19, oy + 6))
                }
            }
        }
        return obstacles
    }
}

extension VM {
    /// What a Sim walking on a level routes around: the level's walls, then the footprints of the
    /// objects and other Sims there that don't let people through, in object ID order. An object
    /// lets people through with "allow person intersection" and not "disallow person
    /// intersection"; other Sims do when this one has "allow person intersection". The Sim's own
    /// group, and anything it holds, are left out.
    ///
    /// The objects' "allow intersection" entry points aren't asked, as placement asks them, since
    /// building the set runs no code; routes find what's in the way when they arrive.
    public func routeObstacles(level: Int, for sim: Entity) throws(SimAnticsError) -> [Obstacle] {
        var obstacles = try architecture.wallObstacles(level: level)
        let letsPeopleThrough = sim.objectData[Int(ObjectVariable.flags.rawValue)] & EntityFlag.allowPersonIntersection != 0
        for other in entities where Int(other.position.level) == level && other.group !== sim.group && other.container !== sim {
            guard let footprint = other.footprint else { continue }
            let flags = other.objectData[Int(ObjectVariable.flags.rawValue)]
            let allowed = (other.isAvatar && letsPeopleThrough)
                || (flags & EntityFlag.disallowPersonIntersection == 0 && flags & EntityFlag.allowPersonIntersection != 0)
            if !allowed { obstacles.append(footprint) }
        }
        return obstacles
    }
}

extension Architecture {
    /// Whether a solid wall (one without a door) stands between two tiles on a level, along the
    /// line from one to the other, tile by tile (Bresenham's line). Where the line steps diagonally
    /// it checks the walls of both ways around the corner, the way it went first. A tile off the
    /// lot has no walls.
    ///
    /// - Throws: ``SimAnticsError/indexOutOfRange(_:)`` for a level past the lot's stories.
    public func wallBetween(tileX x1: Int, y y1: Int, andTileX x2: Int, y y2: Int, level: Int) throws(SimAnticsError) -> Bool {
        guard (1...Self.stories).contains(level) else { throw .indexOutOfRange("level \(level)") }
        let floor = walls[level - 1]
        func tile(_ x: Int, _ y: Int) -> WallTile? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return floor[y * width + x]
        }
        func leftSolid(_ x: Int, _ y: Int) -> Bool {
            guard let wall = tile(x, y) else { return false }
            return wall.segments.contains(.topLeft) && !wall.topLeftDoor
        }
        func rightSolid(_ x: Int, _ y: Int) -> Bool {
            guard let wall = tile(x, y) else { return false }
            return wall.segments.contains(.topRight) && !wall.topRightDoor
        }

        var x = x1, y = y1
        let xStep = x2 >= x1 ? 1 : -1, yStep = y2 >= y1 ? 1 : -1
        let dx = abs(x2 - x1), dy = abs(y2 - y1)
        // A line longer than any lot comes from positions off it; it has nothing to cross.
        guard dx <= 1024, dy <= 1024 else { return false }
        let xAhead = xStep > 0 ? 1 : 0, yAhead = yStep > 0 ? 1 : 0
        let ddx = dx * 2, ddy = dy * 2

        if ddx >= ddy {
            var error = dx, previous = dx
            for _ in 0..<dx {
                let oldX = x, oldY = y
                x += xStep
                error += ddy
                if error > ddx {
                    y += yStep
                    error -= ddx
                    if error + previous < ddx {
                        if leftSolid(oldX + xAhead, oldY) || rightSolid(x, oldY + yAhead) { return true }
                    } else {
                        if rightSolid(oldX, oldY + yAhead) || leftSolid(oldX + xAhead, y) { return true }
                    }
                } else if leftSolid(oldX + xAhead, oldY) {
                    return true
                }
                previous = error
            }
        } else {
            var error = dy, previous = dy
            for _ in 0..<dy {
                let oldX = x, oldY = y
                y += yStep
                error += ddx
                if error > ddy {
                    x += xStep
                    error -= ddy
                    if error + previous < ddy {
                        if rightSolid(oldX, oldY + yAhead) || leftSolid(oldX + xAhead, y) { return true }
                    } else {
                        if leftSolid(oldX + xAhead, oldY) || rightSolid(x, oldY + yAhead) { return true }
                    }
                } else if rightSolid(oldX, oldY + yAhead) {
                    return true
                }
                previous = error
            }
        }
        return false
    }
}
