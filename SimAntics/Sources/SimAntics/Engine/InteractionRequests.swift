import TSOFiles

/// Why a player's request for an interaction was turned down.
public enum InteractionRequestError: Error, Equatable, Sendable {
    /// Only Sims choose interactions.
    case notASim(objectID: Int16)
    /// The object has no interaction with that number.
    case noInteraction(UInt32)
    /// The interaction's action tree doesn't exist.
    case noActionTree(UInt32)
    /// The Sim may not use it now: who it is (a visitor, carrying something, a pet), or the
    /// interaction's check tree.
    case notAllowed(UInt32)
    /// The object offers no menus: it's unseen, such as the lot's controllers and trackers.
    case notOffered(objectID: Int16)
    /// Reading the interaction, or running its check tree's setup, failed.
    case simantics(SimAnticsError)
}

extension Entity {
    /// Whether a player can open the object's pie menu: it has graphics, isn't hidden (object
    /// data `hidden`), and isn't one of the lot's controllers (object type 7).
    ///
    /// The controllers and trackers keep their interactions for the game's own use: a skill
    /// tracker's check tree, for one, deletes the object that runs it, and a death controller's
    /// interactions kill the Sim. A player never sees them, so they're never offered.
    public var offersMenus: Bool {
        let definition = object.definition
        return definition.numGraphics > 0
            && objectData[Int(ObjectVariable.hidden.rawValue)] == 0
            && definition.objectType != OBJD.ObjectType.simType.rawValue
    }
}

extension VM {
    /// The interactions a Sim may choose on an object now, in table order: those whose action
    /// tree exists and that pass ``VMThread/mayRun(_:)`` for the Sim, as a pie menu would offer
    /// them. None for an object that offers no menus (``Entity/offersMenus``).
    ///
    /// Running each check tree changes nothing a lot keeps: a check runs on a copy of the Sim's
    /// temps outside a tick.
    public func availableInteractions(on object: Entity, for sim: Entity) throws(InteractionRequestError) -> [Interaction] {
        guard sim.isAvatar else { throw .notASim(objectID: sim.objectID) }
        guard object.offersMenus else { return [] }
        var offered: [Interaction] = []
        do {
            for interaction in try interactions(of: object.object) {
                guard let action = try QueuedAction(interaction, of: object), sim.thread.mayRun(action) else { continue }
                offered.append(interaction)
            }
        } catch {
            throw .simantics(error)
        }
        return offered
    }

    /// Queues one of an object's interactions for a Sim, as a player choosing it from the pie
    /// menu, and returns the action's ID, for ``cancelInteraction(id:for:)``.
    ///
    /// The action is user-driven, with the object as callee and stack object, and goes into the
    /// Sim's queue (``VMThread/enqueue(_:)``) if the Sim may use it now and the object offers
    /// menus (``Entity/offersMenus``). Call it between ticks;
    /// the Sim's main runs it when it next idles for input.
    @discardableResult
    public func queueInteraction(_ number: UInt32, on object: Entity, for sim: Entity) throws(InteractionRequestError) -> UInt16 {
        guard sim.isAvatar else { throw .notASim(objectID: sim.objectID) }
        guard object.offersMenus else { throw .notOffered(objectID: object.objectID) }
        let table: [Interaction]
        do { table = try interactions(of: object.object) } catch { throw .simantics(error) }
        guard let interaction = table.first(where: { $0.number == number }) else { throw .noInteraction(number) }
        let made: QueuedAction?
        do { made = try QueuedAction(interaction, of: object) } catch { throw .simantics(error) }
        guard let action = made else { throw .noActionTree(number) }
        guard sim.thread.mayRun(action) else { throw .notAllowed(number) }
        return sim.thread.enqueue(action)
    }

    /// Cancels one of a Sim's queued actions by ID, as a player clicking it in the queue; `false`
    /// if it has none with that ID. See ``VMThread/cancelAction(id:)``.
    @discardableResult
    public func cancelInteraction(id: UInt16, for sim: Entity) -> Bool {
        sim.thread.cancelAction(id: id)
    }
}
