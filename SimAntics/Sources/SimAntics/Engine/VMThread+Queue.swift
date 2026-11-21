extension VMThread {
    // MARK: Queueing

    /// Adds an action to the queue, gives it the next ID, and returns that ID.
    ///
    /// An action to run immediately goes to the back, hidden (idle mode, the lowest priority), and
    /// the next tick moves it to the front and runs it. A leapfrogging action goes right after the
    /// running ones. Anything else goes after the last waiting action with the same or a higher
    /// priority, or after a parent-exit action, so a higher priority waits less; a parent-idle
    /// action passes parent-exit actions until it reaches its parent's. Then a waiting action
    /// with a higher priority than the running one cancels it.
    @discardableResult
    public func enqueue(_ action: QueuedAction) -> UInt16 {
        var action = action
        action.id = nextActionID
        nextActionID &+= 1
        queueIsDirty = true
        if !isCheck && action.flags.contains(.runImmediately) {
            action.mode = .idle
            action.priority = .min
            queue.append(action)
            return action.id
        }
        let afterRunning = min(max(activeQueueBlock + 1, 0), queue.count)
        if queue.isEmpty {
            queue.append(action)
        } else if action.flags.contains(.leapfrog) {
            queue.insert(action, at: afterRunning)
        } else {
            var passedParent = action.mode != .parentIdle
            var index = queue.count - 1
            var placed = false
            while index >= afterRunning {
                if passedParent && (action.priority <= queue[index].priority || queue[index].mode == .parentExit) {
                    queue.insert(action, at: index + 1)
                    placed = true
                    break
                }
                if queue[index].mode == .parentExit { passedParent = true }
                index -= 1
            }
            if !placed { queue.insert(action, at: afterRunning) }
        }
        evaluatePriorities()
        return action.id
    }

    /// Cancels the queued action with an ID; `false` if there's none.
    ///
    /// The action is marked cancelled. A parent-idle action takes the parent-idle actions after
    /// it with it, and makes the parent-exit actions after it look cancelled at priority 0. A
    /// normal action that isn't running is taken out, and its object runs its queue-skipped entry
    /// point; a running one gets the entity's interaction-cancelled flag and priority 0, and its
    /// routine decides when to stop.
    @discardableResult
    public func cancelAction(id: UInt16) -> Bool {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return false }
        queueIsDirty = true
        queue[index].isCancelled = true
        if queue[index].mode == .parentIdle {
            var later = index + 1
            while later < queue.count {
                switch queue[later].mode {
                case .parentIdle:
                    queue.remove(at: later)
                    continue
                case .parentExit:
                    queue[later].isCancelled = true
                    queue[later].priority = 0
                default:
                    break
                }
                later += 1
            }
        }
        let mainIsRunning = stack.last.map { !$0.isActionTree } ?? false
        if (index > activeQueueBlock || mainIsRunning) && queue[index].mode == .normal {
            let skipped = queue.remove(at: index)
            if let callee = skipped.callee {
                do { try callee.executeEntryPoint(.queueSkipped, runImmediately: true) } catch { vm.report(error, by: callee) }
            }
        } else {
            entity.setFlag(EntityFlag.interactionCanceled, true)
            queue[index].priority = 0
        }
        return true
    }

    // MARK: Running

    /// Runs the first action in the queue that may run, dropping the ones before it that may
    /// not, and returns whether one started. Idle For Input calls it from main.
    ///
    /// A cancelled action sets the interaction-cancelled flag; while it's set, a parent-idle
    /// action is dropped. Each action must pass ``mayRun(_:)``. A check thread runs the first
    /// action without checking.
    func attemptPush() -> Bool {
        queueIsDirty = true
        while let action = queue.first {
            if action.isCancelled { entity.setFlag(EntityFlag.interactionCanceled, true) }
            let canceledParent = action.mode == .parentIdle && entity.hasFlag(EntityFlag.interactionCanceled)
            if isCheck || (!canceledParent && mayRun(action)) {
                run(action)
                return true
            }
            queue.removeFirst()
        }
        return false
    }

    /// Whether the entity may run an action: who it is, then the action's check tree.
    ///
    /// For a Sim, unless the action must run: nothing while carrying unless it allows that;
    /// cats' and dogs' actions only for pets of that kind, and no others for pets; never a
    /// repair; debug actions only for admins (with no check tree). Then the action's permissions:
    /// the object's owner (or anyone using a Sim) may; otherwise visitors, roommates, and ghosts
    /// the permissions leave out may not, nor anyone but admins where they're for staff. An
    /// action that allows visitors, or ghosts when it's available when dead, adds them. Then,
    /// unless it must run without checking always, its check tree must return true.
    public func mayRun(_ action: QueuedAction) -> Bool {
        let flags = action.flags
        if !flags.contains(.mustRun) && entity.isAvatar {
            if entity.slot(0) != nil && !flags.contains(.availableWhenCarrying) { return false }
            let isCat = entity.sim.kind == .cat, isDog = entity.sim.kind == .dog
            if !flags.isDisjoint(with: [.allowCats, .allowDogs]) {
                guard isCat || isDog else { return false }
                if isCat && !flags.contains(.allowCats) { return false }
                if isDog && !flags.contains(.allowDogs) { return false }
            } else if isCat || isDog {
                return false
            }
            if flags.contains(.isRepair) { return false }

            var state: Interaction.Permissions = [.friends]
            if action.callee.map({ $0.isAvatar || entity.persistID == $0.ownerID }) ?? true { state.insert(.objectOwner) }
            let permissions = entity.sim.permissions
            if permissions == .visitor { state.insert(.visitors) }
            if permissions >= .roommate { state.insert(.roommates) }
            if permissions == .admin { state.insert(.staff) }
            if entity.personData[PersonData.isGhost] > 0 { state.insert(.ghosts) }

            var allowed = action.permissions
            if allowed == .nonEmpty { allowed.formUnion([.friends, .roommates, .objectOwner]) }
            if flags.contains(.debug) { return state.contains(.staff) }
            if flags.contains(.availableWhenDead) { allowed.insert(.ghosts) }
            if flags.contains(.allowVisitors) { allowed.insert(.visitors) }
            if state.intersection(allowed).isDisjoint(with: .objectOwner) {
                let barred = Interaction.Permissions(rawValue: ~allowed.rawValue).intersection([.visitors, .roommates, .ghosts])
                if !barred.isDisjoint(with: state) { return false }
                if allowed.contains(.staff) && !state.contains(.staff) { return false }
            }
        }
        guard !flags.contains(.mustRun) || flags.contains(.runCheckAlways), let check = action.checkTree else { return true }
        let frame = StackFrame(thread: self, routine: check, caller: entity, callee: action.callee, codeOwner: action.codeOwner)
        frame.stackObject = action.stackObject
        frame.arguments = [0, 0, 0, 0]
        return VMThread.evaluateCheck(entity: entity, frame: frame) == .returnTrue
    }

    /// Looks over the queue after it changes: waiting actions on objects that are gone are
    /// dropped, and one with a higher priority than the running action cancels it.
    func evaluatePriorities() {
        guard let head = queue.first else { return }
        var index = max(activeQueueBlock + 1, 0)
        while index < queue.count {
            if queue[index].callee?.isDead ?? true {
                queue.remove(at: index)
                continue
            }
            if queue[index].priority > head.priority {
                queue[0].isCancelled = true
                entity.setFlag(EntityFlag.interactionCanceled, true)
            }
            index += 1
        }
    }

    /// Moves an action to run immediately to the front and starts it, when it isn't running
    /// already.
    func runImmediately() {
        guard let index = queue.firstIndex(where: { $0.flags.contains(.runImmediately) }) else { return }
        guard index > activeQueueBlock || stack.last?.isActionTree != true else { return }
        let action = queue.remove(at: index)
        queue.insert(action, at: 0)
        run(action)
    }

    /// Pushes an action's tree, which returns to the queue when it ends, and protects it.
    private func run(_ action: QueuedAction) {
        let frame = action.frame(on: self)
        frame.discardsResult = true
        push(frame)
        activeQueueBlock += 1
    }

    /// An action tree's routine ended: its action leaves the queue, and main carries on from
    /// where it handed over. Leaving a normal action clears the interaction-cancelled flag.
    func finishAction() {
        queueIsDirty = true
        if let action = queue.first {
            if action.mode != .parentIdle { entity.setFlag(EntityFlag.interactionCanceled, false) }
            queue.removeFirst()
        }
        activeQueueBlock -= 1
    }

    /// Empties the queue, as a reset does.
    func clearQueue() {
        queue.removeAll()
        queueIsDirty = true
        activeQueueBlock = -1
    }
}
