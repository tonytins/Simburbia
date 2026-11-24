/// Which entities run on which tick.
///
/// Each tick runs the entities scheduled for it, in object ID order; an entity that doesn't
/// schedule itself while running is scheduled for the next tick. After each tick the random
/// seed advances by the number of entities to make clients desync quickly when their entity
/// counts differ.
public final class VMScheduler {
    /// The current tick (`CurrentTickID`). Settable, for tools that set up a lot's state.
    public var currentTick: UInt32 = 0
    /// Whether entities are being run (`RunningNow`); check threads then share their entity's temps.
    public private(set) var isRunning = false
    /// The entity being run, or `Int16.max` between runs (`CurrentObjectID`).
    public private(set) var currentObjectID = Int16.max

    private var schedule: [UInt32: [Entity]] = [:]
    /// Entities deleted while entities were running, deleted once the tick ends (`PendingDeletion`).
    private var pendingDeletion: [Entity] = []

    public init() {}

    /// The IDs of the entities scheduled for a tick, in run order.
    public func scheduledObjectIDs(on tick: UInt32) -> [Int16] {
        (schedule[tick] ?? []).map(\.objectID)
    }

    /// Schedules an entity `delay` ticks from now; entities that run every frame wait at most one.
    public func scheduleTick(for entity: Entity, in delay: UInt32) {
        let delay = delay > 1 && entity.runsEveryTick ? 1 : delay
        scheduleTick(for: entity, on: currentTick &+ delay)
    }

    /// A deleted entity isn't scheduled, and an entity already scheduled for the tick isn't
    /// scheduled twice, so nothing runs more than once a tick.
    public func scheduleTick(for entity: Entity, on tick: UInt32) {
        guard !entity.isDead else { return }
        entity.thread.scheduledTick = tick
        Self.insertInObjectIDOrder(entity, into: &schedule[tick, default: []])
    }

    /// Removes an entity's future run (`DescheduleTick`).
    public func descheduleTick(for entity: Entity) {
        let tick = entity.thread.scheduledTick
        guard tick > currentTick, let index = schedule[tick]?.firstIndex(where: { $0 === entity }) else { return }
        schedule[tick]?.remove(at: index)
    }

    /// Brings an entity's next run forward after something wakes it (`RescheduleInterrupt`): to
    /// later in this tick if the scheduler hasn't reached it yet, otherwise to the next tick. An
    /// entity with no run scheduled, or one due this tick, is left alone.
    public func rescheduleInterrupt(_ entity: Entity) {
        let tick = entity.thread.scheduledTick
        guard tick != currentTick, tick != 0 else { return }
        descheduleTick(for: entity)
        // The check is against this tick's entities, which only a running tick can still reach with
        // a lower object ID than the entity's.
        if entity.objectID > currentObjectID && schedule[currentTick] != nil {
            scheduleTick(for: entity, on: currentTick)
        } else {
            scheduleTick(for: entity, in: 1)
        }
    }

    /// Starts a tick. On tick 0 (a fresh VM), runs scheduled for tick 1 move to the new tick.
    func beginTick(_ tick: UInt32) {
        if currentTick == 0, let first = schedule[1] {
            schedule[tick] = first
            if tick != 1 { schedule[1] = nil }
        }
        currentTick = tick
    }

    /// Runs this tick's entities. Entities scheduled into this tick while it runs also run.
    func runTick(_ vm: VM) {
        isRunning = true
        var index = 0
        while let entities = schedule[currentTick], index < entities.count {
            let entity = entities[index]
            currentObjectID = entity.objectID
            if !entity.isDead { entity.tick() }
            index += 1
        }
        schedule[currentTick] = nil
        vm.random.seed &+= UInt64(vm.entities.count)
        currentObjectID = .max
        isRunning = false
        let deletions = pendingDeletion
        pendingDeletion.removeAll()
        for entity in deletions {
            // An error here is reported against the object, and the tick carries on
            // (DIFF-21).
            do { try vm.delete(entity) } catch { vm.report(error, by: entity) }
        }
    }

    /// Queues an entity to be deleted when the tick ends (`Delete`).
    func deleteAtEndOfTick(_ entity: Entity) {
        pendingDeletion.append(entity)
    }

    /// A binary search for the insertion point by object ID. It keeps the list sorted, and leaves
    /// an entity already in it where it is.
    static func insertInObjectIDOrder(_ entity: Entity, into list: inout [Entity]) {
        if list.contains(where: { $0 === entity }) { return }
        guard !list.isEmpty else {
            list.append(entity)
            return
        }
        let id = Int(entity.objectID) - 1
        var low = 0, high = list.count - 1
        while high - 1 > low {
            let middle = (high + low) / 2
            if id < Int(list[middle].objectID) { high = middle } else { low = middle }
        }
        let position = Int(list[low].objectID) > id ? low : (Int(list[high].objectID) > id ? high : high + 1)
        list.insert(entity, at: position)
    }
}
