import TSOContent
import TSOFiles

/// One entry in an object's pie menu, read from its interaction table (`TTAB`) and the strings
/// beside it (`TTAs`).
///
/// An object's table is the `TTAB` its definition names (`TreeTableID`) in its own file, or in its
/// semi-global when its file has none. The strings come from the `TTAs` with the same ID, in the
/// same file.
public struct Interaction: Sendable, Equatable {
    /// What an interaction allows, from the table's flags (`TTABFlags`). TSO's meanings: bits 9 and
    /// 10 meant cats and dogs in The Sims 1, and the bits the client never reads are kept raw.
    public struct Flags: OptionSet, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let allowVisitors = Flags(rawValue: 1 << 0)
        public static let joinable = Flags(rawValue: 1 << 1)
        /// It runs as soon as it's queued, ahead of everything else.
        public static let runImmediately = Flags(rawValue: 1 << 2)
        public static let allowConsecutive = Flags(rawValue: 1 << 3)
        public static let debug = Flags(rawValue: 1 << 7)
        public static let autoFirstSelect = Flags(rawValue: 1 << 8)
        public static let leapfrog = Flags(rawValue: 1 << 9)
        public static let mustRun = Flags(rawValue: 1 << 10)
        public static let allowDogs = Flags(rawValue: 1 << 11)
        public static let allowCats = Flags(rawValue: 1 << 12)
        public static let availableWhenCarrying = Flags(rawValue: 1 << 16)
        public static let isRepair = Flags(rawValue: 1 << 17)
        public static let runCheckAlways = Flags(rawValue: 1 << 18)
        public static let availableWhenDead = Flags(rawValue: 1 << 19)
    }

    /// Who may use an interaction, from the table's TSO flags (`TSOFlags`, version 10 and up;
    /// earlier tables get 0x1F, everyone but ghosts and staff).
    public struct Permissions: OptionSet, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Set alone, it means the flags were left empty on purpose.
        public static let nonEmpty = Permissions(rawValue: 1 << 0)
        public static let objectOwner = Permissions(rawValue: 1 << 1)
        public static let roommates = Permissions(rawValue: 1 << 2)
        public static let friends = Permissions(rawValue: 1 << 3)
        public static let visitors = Permissions(rawValue: 1 << 4)
        public static let ghosts = Permissions(rawValue: 1 << 5)
        public static let underParentalControl = Permissions(rawValue: 1 << 6)
        /// Staff: only admins see it.
        public static let staff = Permissions(rawValue: 1 << 7)
    }

    /// The interaction's number, its index in the strings (`TTAIndex`), which content passes
    /// around to name it.
    public var number: UInt32
    /// The pie menu text, or empty when the strings have none.
    public var name: String
    /// The routine that runs the interaction, and the one that decides whether it's offered (0
    /// for none).
    public var actionTree: UInt16
    public var checkTree: UInt16
    public var flags: Flags
    public var permissions: Permissions
    /// How the interaction advertises itself to each motive, in motive order.
    public var motiveAdvertisements: [TTAB.MotiveEntry]
    /// Kept as read, for the scoring Simburbia doesn't do (TSO's Sims don't choose their own
    /// actions): the attenuation, the autonomy threshold, and the joining index.
    public var attenuationCode: UInt32
    public var attenuationValue: Float
    public var autonomyThreshold: UInt32
    public var joiningIndex: Int32

    /// An interaction from a table entry and the strings beside it.
    public init(_ entry: TTAB.Interaction, strings: StringTable?) {
        number = entry.ttaIndex
        name = strings?.string(at: Int(entry.ttaIndex)) ?? ""
        actionTree = entry.actionFunction
        checkTree = entry.testFunction
        flags = Flags(rawValue: entry.flags)
        permissions = Permissions(rawValue: entry.tsoFlags)
        motiveAdvertisements = entry.motiveEntries
        attenuationCode = entry.attenuationCode
        attenuationValue = entry.attenuationValue
        autonomyThreshold = entry.autonomyThreshold
        joiningIndex = entry.joiningIndex
    }

    /// An object's interactions, in table order; none when its definition names no table that
    /// either file has.
    ///
    /// - Throws: ``SimAnticsError/simantics(_:)`` if the table or its strings don't parse.
    public static func interactions(of object: GameObject) throws(SimAnticsError) -> [Interaction] {
        let id = object.definition.treeTableID
        var resource: any IFFResource = object.resource
        do {
            var table = try resource.chunk(TTAB.self, id: id)
            if table == nil, let semiGlobal = object.resource.semiGlobal {
                resource = semiGlobal
                table = try semiGlobal.chunk(TTAB.self, id: id)
            }
            guard let table else { return [] }
            let strings = try resource.chunk(TTAs.self, id: id)?.table
            return table.interactions.map { Interaction($0, strings: strings) }
        } catch {
            throw .simantics("TTAB \(id) of \(object.resource.name) doesn't parse: \(error)")
        }
    }
}

/// An interaction waiting in, or running at the head of, a Sim's action queue.
public struct QueuedAction {
    /// How urgent an action is; a higher priority goes ahead of a lower one.
    public enum Priority {
        public static let idle: Int16 = 0
        public static let autonomous: Int16 = 2
        public static let parentExit: Int16 = 30
        public static let parentIdle: Int16 = 40
        public static let userDriven: Int16 = 50
        public static let maximum: Int16 = 100
    }

    /// How an action takes part in the queue.
    public enum Mode: UInt8, Sendable {
        case normal = 0
        /// Runs when the action that pushed it idles.
        case parentIdle
        /// Runs when the action that pushed it ends; hidden until then, and never cancelled or
        /// skipped.
        case parentExit
        case idle
    }

    /// The routine that runs it, and the one that checks it's still offered.
    public var actionTree: Routine
    public var checkTree: Routine?
    /// The object the interaction belongs to, and the one its routines start with selected (the
    /// callee, for an interaction).
    public var callee: Entity?
    public var stackObject: Entity?
    /// Whose files the routines resolve through.
    public var codeOwner: GameObject
    public var name: String
    /// The action tree's arguments: four, all 0, unless whoever queued it says otherwise.
    public var arguments: [Int16] = [0, 0, 0, 0]
    /// The interaction's number in its object's table, or -1 for an action that isn't one.
    public var interactionNumber: Int32 = -1
    public var priority: Int16 = Priority.idle
    public var mode: Mode = .normal
    public var flags: Interaction.Flags = []
    public var permissions: Interaction.Permissions = .everyoneButGhostsAndStaff
    /// A number the queue gives the action, which wraps, so a player can name the one to cancel.
    public var id: UInt16 = 0
    public var isCancelled = false

    public init(actionTree: Routine, checkTree: Routine? = nil, callee: Entity?, stackObject: Entity?,
                codeOwner: GameObject, name: String) {
        self.actionTree = actionTree
        self.checkTree = checkTree
        self.callee = callee
        self.stackObject = stackObject
        self.codeOwner = codeOwner
        self.name = name
    }

    /// The action for one of an object's interactions, user-driven, with the object as callee and
    /// stack object; `nil` when its action tree doesn't exist.
    ///
    /// A check tree that doesn't exist is left out, so the action is always offered.
    ///
    /// - Throws: ``SimAnticsError`` if a routine doesn't parse, or a semi-global routine has no
    ///   semi-global.
    public init?(_ interaction: Interaction, of callee: Entity) throws(SimAnticsError) {
        let vm = callee.vm
        guard let action = try vm.routine(opcode: interaction.actionTree, codeOwner: callee.object) else { return nil }
        self.init(actionTree: action, callee: callee, stackObject: callee, codeOwner: callee.object, name: interaction.name)
        if interaction.checkTree != 0 {
            checkTree = try vm.routine(opcode: interaction.checkTree, codeOwner: callee.object)
        }
        interactionNumber = Int32(bitPattern: interaction.number)
        priority = Priority.userDriven
        flags = interaction.flags
        permissions = interaction.permissions
    }

    /// A frame that runs the action tree on a thread, for its entity, marked as an interaction's.
    func frame(on thread: VMThread) -> StackFrame {
        let frame = StackFrame(thread: thread, routine: actionTree, caller: thread.entity, callee: callee, codeOwner: codeOwner)
        frame.stackObject = stackObject
        frame.arguments = arguments
        frame.isActionTree = true
        return frame
    }
}

extension Interaction.Permissions {
    /// What tables before version 10 get.
    public static let everyoneButGhostsAndStaff = Interaction.Permissions(rawValue: 0x1F)
}

extension VM {
    /// An object's interactions (``Interaction/interactions(of:)``), read once per VM.
    public func interactions(of object: GameObject) throws(SimAnticsError) -> [Interaction] {
        if let table = interactionTables[object.guid] { return table }
        let table = try Interaction.interactions(of: object)
        interactionTables[object.guid] = table
        return table
    }
}
