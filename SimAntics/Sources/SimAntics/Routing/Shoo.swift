extension VM {
    /// The global object a Sim is shooed away from ("Destination - For Go Here & Shoo").
    public static let shooObjectGUID: UInt32 = 0x7C4
    /// Its interaction that walks a Sim off the spot it stands on.
    static let shooInteraction: UInt32 = 3

    /// Whether a Sim has been asked to move and hasn't finished moving: its queue holds the shoo
    /// object's interaction.
    static func isBeingShooed(_ sim: Entity) -> Bool {
        sim.thread.queue.contains { $0.callee?.object.definition.guid == shooObjectGUID }
    }

    /// Asks a Sim standing in another's way to move: places the shoo object where it stands and
    /// queues the object's interaction 3 on it, which walks it off the spot.
    ///
    /// The interaction must run (its check tree isn't run) and queues at user-driven priority, as
    /// if a player had asked. A Sim already asked to move, or the asker itself, isn't asked again.
    ///
    /// - Returns: Whether it was asked; `false` for a blocker that isn't a Sim, one already asked,
    ///   or an install without the shoo object or its interaction.
    /// - Throws: Any error the shoo object's entry points throw as it's created.
    @discardableResult
    public func shoo(_ blocker: Entity, by sim: Entity) throws(SimAnticsError) -> Bool {
        guard blocker.isAvatar, blocker !== sim, !blocker.isDead, !blocker.position.isOutOfWorld, !Self.isBeingShooed(blocker),
              let object = try gameObject(guid: Self.shooObjectGUID),
              let interaction = try interactions(of: object).first(where: { $0.number == Self.shooInteraction }),
              let group = try createObject(guid: Self.shooObjectGUID), let marker = group.leadObject else { return false }
        try place(group, at: blocker.position, facing: .north, flags: .allowIntersection)
        guard var action = try QueuedAction(interaction, of: marker) else {
            try delete(marker, wholeGroup: true)
            return false
        }
        action.priority = QueuedAction.Priority.userDriven
        action.flags.insert(.mustRun)
        blocker.thread.enqueue(action)
        return true
    }
}
