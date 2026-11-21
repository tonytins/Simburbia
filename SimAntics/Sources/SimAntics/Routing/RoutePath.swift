extension RouteFailure: Error {}

/// A way through a room: the points a Sim walks between, from where it stands to a goal.
public struct RoutePath: Sendable, Equatable {
    /// The turning points, the start first and the goal last, in sixteenths of a tile; straight
    /// lines join them.
    public var waypoints: [LotPosition]
    /// Which of the goals it reaches, by its index in the list given.
    public var goal: Int
}

extension VM {
    /// The most grid points a path search may look at, so a route can't stall a tick: about a
    /// room 30 tiles square searched end to end.
    public static let maximumPathSearch = 250_000

    /// Half a Sim's width, in sixteenths: a route keeps the Sim's middle this far out of
    /// everything in its way.
    static let simHalfWidth = 3

    /// The way from a position to the nearest of some goals within one room on one level, for a
    /// Sim (``routeObstacles(level:for:)``).
    ///
    /// The search runs over sixteenths of a tile, eight ways (A*, a straight step costing 10 and a
    /// diagonal one 14), never cutting a blocked corner, and keeps the Sim's middle out of the walls
    /// and footprints in its way, grown by half its width. An obstacle the start or a goal is
    /// already inside is left out, so a Sim at a counter can step away and one can walk up to a
    /// chair. The path found is then smoothed to the turning points the Sim can see between. Equal
    /// choices always go the same way, so a lot routes the same on every machine.
    ///
    /// - Returns: The path, or why there's none: `noRoomRoute` when every goal is in another room
    ///   or on another level (doors and stairs come later), and `noPath` when none can be reached,
    ///   or the search passes ``maximumPathSearch`` points.
    /// - Throws: ``SimAnticsError`` for a start off the lot's levels.
    public func findPath(for sim: Entity, from start: LotPosition, to goals: [RouteGoal]) throws(SimAnticsError)
        -> Result<RoutePath, RouteFailure> {
        guard !goals.isEmpty else { return .failure(.noValidGoals) }
        let level = Int(start.level)
        let room = architecture.room(at: start)
        let reachable = goals.indices.filter { index in
            let goal = goals[index].position
            return Int(goal.level) == level && !architecture.isOutOfBounds(goal) && architecture.room(at: goal) == room
        }
        guard !reachable.isEmpty else { return .failure(.noRoomRoute) }

        let grown = try routeObstacles(level: level, for: sim).map { obstacle in
            Obstacle(obstacle.x1 - Self.simHalfWidth, obstacle.y1 - Self.simHalfWidth,
                     obstacle.x2 + Self.simHalfWidth, obstacle.y2 + Self.simHalfWidth)
        }
        let points = [start] + reachable.map { goals[$0].position }
        let obstacles = grown.filter { obstacle in !points.contains { obstacle.strictlyContains($0) } }
        var grid = RouteGrid(architecture: architecture, level: level, room: room, obstacles: obstacles)

        let goalCells = reachable.map { (index: $0, cell: Cell(goals[$0].position)) }
        guard let (cells, reached) = grid.search(from: Cell(start), to: goalCells.map(\.cell), limit: Self.maximumPathSearch) else {
            return .failure(.noPath)
        }
        let smoothed = grid.smooth(cells)
        let waypoints = smoothed.map { LotPosition(x: Int16(truncatingIfNeeded: $0.x), y: Int16(truncatingIfNeeded: $0.y), level: start.level) }
        return .success(RoutePath(waypoints: waypoints, goal: goalCells[reached].index))
    }
}

extension Obstacle {
    /// Whether a point is inside, not on an edge.
    func strictlyContains(_ point: LotPosition) -> Bool {
        let x = Int(point.x), y = Int(point.y)
        return x > x1 && x < x2 && y > y1 && y < y2
    }

    func strictlyContains(_ cell: Cell) -> Bool {
        cell.x > x1 && cell.x < x2 && cell.y > y1 && cell.y < y2
    }
}

/// A grid point, in sixteenths of a tile.
struct Cell: Hashable {
    var x: Int
    var y: Int

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    init(_ position: LotPosition) {
        x = Int(position.x)
        y = Int(position.y)
    }
}

/// The grid a path search walks: which points a Sim's middle may be at, worked out as they're
/// first reached and remembered.
struct RouteGrid {
    let architecture: Architecture
    let level: Int
    let room: UInt16
    let obstacles: [Obstacle]
    /// The obstacles touching each tile, by its index on the level, so a point checks only those.
    private var byTile: [Int: [Int]] = [:]
    private var known: [Cell: Bool] = [:]
    private var roomOfTile: [Int: Bool] = [:]

    init(architecture: Architecture, level: Int, room: UInt16, obstacles: [Obstacle]) {
        self.architecture = architecture
        self.level = level
        self.room = room
        self.obstacles = obstacles
        for (index, obstacle) in obstacles.enumerated() {
            let fromX = max(0, obstacle.x1 >> 4), toX = min(architecture.width - 1, obstacle.x2 >> 4)
            let fromY = max(0, obstacle.y1 >> 4), toY = min(architecture.height - 1, obstacle.y2 >> 4)
            guard fromX <= toX, fromY <= toY else { continue }
            for y in fromY...toY {
                for x in fromX...toX { byTile[y * architecture.width + x, default: []].append(index) }
            }
        }
    }

    /// Whether the Sim's middle may be at a point: on the lot, in the room, and inside nothing.
    mutating func isOpen(_ cell: Cell) -> Bool {
        if let open = known[cell] { return open }
        let open = computeOpen(cell)
        known[cell] = open
        return open
    }

    private mutating func computeOpen(_ cell: Cell) -> Bool {
        let tileX = cell.x >> 4, tileY = cell.y >> 4
        guard cell.x >= 0, cell.y >= 0, tileX < architecture.width, tileY < architecture.height else { return false }
        let tile = tileY * architecture.width + tileX
        let inRoom: Bool
        if let known = roomOfTile[tile] {
            inRoom = known
        } else {
            let position = LotPosition(x: Int16(truncatingIfNeeded: cell.x), y: Int16(truncatingIfNeeded: cell.y), level: Int8(level))
            inRoom = architecture.room(at: position) == room
            roomOfTile[tile] = inRoom
        }
        guard inRoom else { return false }
        for index in byTile[tile] ?? [] where obstacles[index].strictlyContains(cell) { return false }
        return true
    }

    /// The eight steps, straight ones first, each with its cost.
    private static let steps: [(dx: Int, dy: Int, cost: Int)] = [
        (0, -1, 10), (1, 0, 10), (0, 1, 10), (-1, 0, 10), (1, -1, 14), (1, 1, 14), (-1, 1, 14), (-1, -1, 14),
    ]

    /// The cheapest way to any of the goals (A*), as the points along it, and which goal it
    /// reached; `nil` when none can be reached within `limit` points.
    mutating func search(from start: Cell, to goals: [Cell], limit: Int) -> ([Cell], Int)? {
        func estimate(_ cell: Cell) -> Int {
            goals.map { goal in
                let dx = abs(goal.x - cell.x), dy = abs(goal.y - cell.y)
                return 10 * max(dx, dy) + 4 * min(dx, dy)
            }.min() ?? 0
        }
        var open = RouteHeap()
        var cost: [Cell: Int] = [start: 0]
        var came: [Cell: Cell] = [:]
        var order = 0
        open.push(cost: estimate(start), spent: 0, order: order, cell: start)
        var looked = 0
        while let current = open.pop() {
            guard current.spent == cost[current.cell] else { continue }   // a stale entry
            if let reached = goals.firstIndex(of: current.cell) {
                var path = [current.cell]
                while let previous = came[path[path.count - 1]] { path.append(previous) }
                return (path.reversed(), reached)
            }
            looked += 1
            if looked > limit { return nil }
            for step in Self.steps {
                let next = Cell(x: current.cell.x + step.dx, y: current.cell.y + step.dy)
                guard isOpen(next) else { continue }
                if step.dx != 0 && step.dy != 0 {
                    // No cutting a blocked corner.
                    guard isOpen(Cell(x: current.cell.x + step.dx, y: current.cell.y)),
                          isOpen(Cell(x: current.cell.x, y: current.cell.y + step.dy)) else { continue }
                }
                let spent = current.spent + step.cost
                if let known = cost[next], known <= spent { continue }
                cost[next] = spent
                came[next] = current.cell
                order += 1
                open.push(cost: spent + estimate(next), spent: spent, order: order, cell: next)
            }
        }
        return nil
    }

    /// The path cut down to the points a Sim must turn at: from each, the farthest later point it
    /// can walk to in a straight line.
    mutating func smooth(_ path: [Cell]) -> [Cell] {
        guard path.count > 2 else { return path }
        var result = [path[0]]
        var from = 0
        while from < path.count - 1 {
            var to = path.count - 1
            while to > from + 1 && !isClear(path[from], path[to]) { to -= 1 }
            result.append(path[to])
            from = to
        }
        return result
    }

    /// Whether a straight walk between two points stays open, checked at every grid point along
    /// it (Bresenham's line), corners included.
    private mutating func isClear(_ a: Cell, _ b: Cell) -> Bool {
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var error = dx + dy
        while true {
            guard isOpen(Cell(x: x, y: y)) else { return false }
            if x == b.x && y == b.y { return true }
            let doubled = 2 * error
            var movedX = false, movedY = false
            if doubled >= dy { error += dy; x += sx; movedX = true }
            if doubled <= dx { error += dx; y += sy; movedY = true }
            if movedX && movedY {
                guard isOpen(Cell(x: x - sx, y: y)), isOpen(Cell(x: x, y: y - sy)) else { return false }
            }
        }
    }
}

/// The search's open points, cheapest first: by estimated total cost, then by the most already
/// spent (nearer the goal), then by the order they were found.
struct RouteHeap {
    struct Entry {
        var cost: Int
        var spent: Int
        var order: Int
        var cell: Cell
    }

    private var entries: [Entry] = []

    private static func before(_ a: Entry, _ b: Entry) -> Bool {
        if a.cost != b.cost { return a.cost < b.cost }
        if a.spent != b.spent { return a.spent > b.spent }
        return a.order < b.order
    }

    mutating func push(cost: Int, spent: Int, order: Int, cell: Cell) {
        entries.append(Entry(cost: cost, spent: spent, order: order, cell: cell))
        var child = entries.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.before(entries[child], entries[parent]) else { break }
            entries.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Entry? {
        guard let first = entries.first else { return nil }
        let last = entries.removeLast()
        if !entries.isEmpty {
            entries[0] = last
            var parent = 0
            while true {
                let left = 2 * parent + 1, right = left + 1
                var best = parent
                if left < entries.count && Self.before(entries[left], entries[best]) { best = left }
                if right < entries.count && Self.before(entries[right], entries[best]) { best = right }
                guard best != parent else { break }
                entries.swapAt(parent, best)
                parent = best
            }
        }
        return first
    }
}
