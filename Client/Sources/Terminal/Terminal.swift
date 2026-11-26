import Foundation
import SimAntics

/// The commands the client's drop-down terminal runs on a lot, a line at a time: joining a Sim,
/// listing objects and what a Sim may do with them, and queueing and cancelling interactions
/// (through ``VM/queueInteraction(_:on:for:)`` and its siblings).
///
/// Every command answers with lines to show; nothing it's given can crash it. The commands act
/// for one Sim, the one last joined or picked with `sim`. They change the lot between ticks, as a
/// player's clicks would.
public struct TerminalCommands {
    /// The Sims `join` can bring, the first the install has: TSO's template person, then
    /// MockInstall's Sim.
    public static let templates: [UInt32] = [VM.templatePerson, 0x4D4F_4307]

    /// The persist IDs joined Sims get, from this one up; made up, and clear of a lot's own.
    static let firstPersistID: UInt32 = 0x5B1D_0001

    /// The Sim the commands act for, by object ID.
    public private(set) var simID: Int16?
    private var joined: UInt32 = 0

    public init() {}

    public static let help = [
        "join [name]           bring a Sim onto the lot, and act for it",
        "sim <id>              act for another Sim",
        "sims                  the Sims on the lot",
        "objects [text]        objects, by ID, whose name has the text",
        "menu <object>         what the Sim may do with an object",
        "queue <object> <n>    queue interaction n on an object",
        "cancel <action>       cancel a queued action by its ID",
        "show                  the Sim's queue",
        "clear                 clear the terminal",
    ]

    /// Runs one line and returns what to show. `clear` returns no lines; the terminal empties
    /// itself.
    public mutating func run(_ line: String, on vm: VM) -> [String] {
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = words.first?.lowercased() else { return [] }
        let arguments = Array(words.dropFirst())
        switch command {
        case "help", "?": return Self.help
        case "join": return join(name: arguments.isEmpty ? nil : arguments.joined(separator: " "), on: vm)
        case "sim": return pickSim(arguments, on: vm)
        case "sims": return sims(on: vm)
        case "objects": return objects(matching: arguments.joined(separator: " "), on: vm)
        case "menu": return menu(arguments, on: vm)
        case "queue": return queue(arguments, on: vm)
        case "cancel": return cancel(arguments, on: vm)
        case "show": return show(on: vm)
        case "clear": return []
        default: return ["unknown command '\(command)'; try help"]
        }
    }

    // MARK: Commands

    private mutating func join(name: String?, on vm: VM) -> [String] {
        guard let template = Self.templates.first(where: { (try? vm.content.objects.object(guid: $0)) != nil }) else {
            return ["this install has no Sim to join"]
        }
        joined += 1
        let identity = SimIdentity(name: name ?? "Player \(joined)", persistID: Self.firstPersistID &+ joined - 1,
                                   bodyOutfit: 0x24C_0000_000D)
        do {
            guard let sim = try vm.joinSim(template: template, identity: identity) else { return ["the Sim couldn't be made"] }
            simID = sim.objectID
            return ["\(sim.sim.name) joined as \(sim.objectID)"]
        } catch {
            return ["the Sim couldn't join: \(error)"]
        }
    }

    private mutating func pickSim(_ arguments: [String], on vm: VM) -> [String] {
        guard arguments.count == 1, let id = Int16(arguments[0]) else { return ["usage: sim <id>"] }
        guard let entity = vm.entity(id: id), entity.isAvatar else { return ["\(id) isn't a Sim"] }
        simID = id
        return ["acting for \(entity.sim.name) (\(id))"]
    }

    private func sims(on vm: VM) -> [String] {
        let sims = vm.entities.filter(\.isAvatar)
        guard !sims.isEmpty else { return ["no Sims; try join"] }
        return sims.map { "\($0.objectID)  \($0.sim.name)" + ($0.objectID == simID ? "  (acting for)" : "") }
    }

    private func objects(matching text: String, on vm: VM) -> [String] {
        let matches = vm.entities.filter { entity in
            text.isEmpty || Inspection(entity).title.localizedCaseInsensitiveContains(text)
        }
        guard !matches.isEmpty else { return ["no objects match"] }
        return matches.map { "\($0.objectID)  \(Inspection($0).title)" }
    }

    private func menu(_ arguments: [String], on vm: VM) -> [String] {
        let resolved: (sim: Entity, object: Entity)
        switch resolve(arguments.first, usage: "menu <object>", on: vm) {
        case .success(let pair): resolved = pair
        case .failure(let message): return [message.text]
        }
        do {
            let offered = try vm.availableInteractions(on: resolved.object, for: resolved.sim)
            guard !offered.isEmpty else { return ["\(Inspection(resolved.object).title) offers \(resolved.sim.sim.name) nothing now"] }
            return offered.map { "\($0.number)  \($0.name.isEmpty ? "(unnamed)" : $0.name)" }
        } catch {
            return [Self.describe(error)]
        }
    }

    private func queue(_ arguments: [String], on vm: VM) -> [String] {
        guard arguments.count == 2, let number = UInt32(arguments[1]) else { return ["usage: queue <object> <n>"] }
        let resolved: (sim: Entity, object: Entity)
        switch resolve(arguments[0], usage: "queue <object> <n>", on: vm) {
        case .success(let pair): resolved = pair
        case .failure(let message): return [message.text]
        }
        do {
            let id = try vm.queueInteraction(number, on: resolved.object, for: resolved.sim)
            return ["queued as action \(id)"]
        } catch {
            return [Self.describe(error)]
        }
    }

    private func cancel(_ arguments: [String], on vm: VM) -> [String] {
        guard arguments.count == 1, let id = UInt16(arguments[0]) else { return ["usage: cancel <action>"] }
        guard let sim = currentSim(on: vm) else { return ["no Sim; try join"] }
        return [vm.cancelInteraction(id: id, for: sim) ? "cancelling action \(id)" : "\(sim.sim.name) has no action \(id)"]
    }

    private func show(on vm: VM) -> [String] {
        guard let sim = currentSim(on: vm) else { return ["no Sim; try join"] }
        let queue = sim.thread.queue
        guard !queue.isEmpty else { return ["\(sim.sim.name)'s queue is empty"] }
        return queue.enumerated().map { index, action in
            let state = index <= sim.thread.activeQueueBlock ? "running" : "waiting"
            return "\(action.id)  \(action.name)  on \(action.callee?.objectID ?? 0)  \(state)" + (action.isCancelled ? ", cancelled" : "")
        }
    }

    // MARK: Helpers

    private struct Message: Error {
        var text: String
    }

    private func currentSim(on vm: VM) -> Entity? {
        guard let simID, let sim = vm.entity(id: simID), sim.isAvatar else { return nil }
        return sim
    }

    /// The Sim acted for and the object an argument names, or why not.
    private func resolve(_ argument: String?, usage: String, on vm: VM) -> Result<(sim: Entity, object: Entity), Message> {
        guard let argument, let id = Int16(argument) else { return .failure(Message(text: "usage: \(usage)")) }
        guard let sim = currentSim(on: vm) else { return .failure(Message(text: "no Sim; try join")) }
        guard let object = vm.entity(id: id) else { return .failure(Message(text: "no object \(id)")) }
        return .success((sim, object))
    }

    static func describe(_ error: InteractionRequestError) -> String {
        switch error {
        case .notASim(let id): "\(id) isn't a Sim"
        case .noInteraction(let number): "no interaction \(number) there"
        case .noActionTree(let number): "interaction \(number) has no routine to run"
        case .notAllowed(let number): "the Sim may not do \(number) now"
        case .notOffered(let id): "\(id) offers no menus"
        case .simantics(let error): "that failed: \(error)"
        }
    }
}
