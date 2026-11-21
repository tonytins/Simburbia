extension Entity {
    /// Whether one of the object flags (object data 8, ``EntityFlag``) is set.
    func hasFlag(_ flag: Int16) -> Bool {
        objectData[Int(ObjectVariable.flags.rawValue)] & flag != 0
    }

    /// Sets or clears one of the object flags directly, without the footprint update a routine's
    /// write to them makes.
    func setFlag(_ flag: Int16, _ isSet: Bool) {
        let index = Int(ObjectVariable.flags.rawValue)
        objectData[index] = isSet ? objectData[index] | flag : objectData[index] & ~flag
    }

    /// The Sims using this object, in object ID order: those with any part of it as the callee of
    /// a routine on their stack or of an action in their queue (object data `UseCount`).
    var users: [Entity] {
        let parts = group.objects
        return vm.entities.filter { sim in
            sim.isAvatar && (sim.thread.stack.contains { frame in parts.contains { $0 === frame.callee } }
                || sim.thread.queue.contains { action in parts.contains { $0 === action.callee } })
        }
    }

    /// Whether the object, or any part of it, is in use: occupied, or the callee of a routine on a
    /// Sim's stack. Unlike ``users``, a queued action doesn't count.
    var isInUse: Bool {
        group.objects.contains { part in
            part.hasFlag(EntityFlag.occupied) || vm.entities.contains { sim in
                sim.isAvatar && sim.thread.stack.contains { $0.callee === part }
            }
        }
    }
}
