import Foundation
import SimAntics
import TSOContent
import TSOFiles

/// Runs lots on Simburbia's VM for the study: a lot loaded from a blueprint, ticked, and recorded
/// as a digest line every so often, so two runs of the same seed can be set side by side.
///
/// Where a run reaches something Simburbia doesn't support yet, it says so with an `unsupported`
/// line, and the study sets the object that reached it aside.
public struct LotRunner {
    public let content: GameContent

    public init(content: GameContent) {
        self.content = content
    }

    /// The seed a run uses unless told otherwise.
    public static let defaultSeed: UInt64 = 0x0F50_D0C5_EED0_0001

    /// Visitor Sims to join a lot after it loads, as players join one.
    public struct Sims: Sendable, Equatable {
        public var count: Int
        public var template: UInt32

        public init(count: Int, template: UInt32 = VM.templatePerson) {
            self.count = count
            self.template = template
        }

        /// Sim `n`'s made-up identity: "Oracle Sim n", persist ID `0x0AC1E000 + n`, a visitor,
        /// male, skin tone 0, in the default daywear, with every motive and persisted value at 0.
        public static func identity(_ n: Int) -> SimIdentity {
            var identity = SimIdentity(name: "Oracle Sim \(n)", persistID: 0x0AC1_E000 &+ UInt32(truncatingIfNeeded: n),
                                       bodyOutfit: 0x24C_0000_000D)
            identity.headOutfit = 0
            return identity
        }
    }

    /// A VM with a lot loaded: the blueprint, then the tick the load runs in, then the random seed
    /// set again, so the first digest starts from the seed. With `sims`, they join after the load
    /// (``SimAntics/VM/joinSim(template:)``), inside a tick of their own, and the seed is set again
    /// after it.
    func loadedLot(_ blueprint: Blueprint, seed: UInt64, sims: Sims? = nil,
                   recordsCoverage: Bool = false) throws(SimAnticsError) -> (VM, [VM.LeftOut]) {
        let vm = try VM(content: content, seed: seed)
        vm.recordsCoverage = recordsCoverage
        let leftOut = try vm.load(blueprint)
        vm.tick()
        vm.random = VMRandom(seed: seed)
        if let sims, sims.count > 0 {
            for n in 1...sims.count { try vm.joinSim(template: sims.template, identity: Sims.identity(n)) }
            vm.tick()
            vm.random = VMRandom(seed: seed)
        }
        return (vm, leftOut)
    }

    private static func digest(of vm: VM, tick: Int) -> String {
        "tick \(tick) seed \(String(format: "%016llx", vm.random.seed)) entities \(vm.entities.count) digest \(StateDigest.hex(of: vm))"
    }

    /// What's unsupported first among reported errors, by the object that reached it
    /// (`" by 0x1A2B3C4D: reason"`, or `": reason"` for an object gone since), so the study can set
    /// that object aside. `nil` if nothing is.
    public static func firstGap(in reported: [(objectID: Int16, error: SimAnticsError)], guid: (Int16) -> UInt32?) -> String? {
        for report in reported {
            guard case .unsupported(let reason) = report.error else { continue }
            let by = guid(report.objectID).map { String(format: " by 0x%08X", $0) } ?? ""
            return "\(by): \(reason)"
        }
        return nil
    }

    /// A lot loaded with its objects, then ticked: `tick N seed S entities E digest D` after
    /// loading, every `every` ticks, and at the end. Once a thread reaches something not supported
    /// yet, the run stops there with `unsupported at tick N by 0xGUID:` (the object that reached
    /// it) and what wasn't supported, and no digest for that tick; `N` is 0 if loading reached it.
    /// Other failures give `error`. Objects left out of the lot are reported through `leftOut`.
    ///
    /// With `checksRules`, the lot's rules (`LotRule`) are checked after loading and every game
    /// minute; the first broken one stops the run with `broken at tick N by 0xGUID: rule: detail`.
    /// Checking reads the state only, so the digests are the same either way. With `coverage`, the
    /// instructions the run reached, loading included, are added to it, however the run ends.
    public func lotRun(_ lot: Blueprint, ticks: Int, every: Int, seed: UInt64 = LotRunner.defaultSeed,
                       sims: Sims? = nil, checksRules: Bool = false, coverage: Coverage? = nil,
                       leftOut: (VM.LeftOut) -> Void = { _ in }) -> [String] {
        let vm: VM
        do {
            let loaded = try loadedLot(lot, seed: seed, sims: sims, recordsCoverage: coverage != nil)
            vm = loaded.0
            loaded.1.forEach(leftOut)
        } catch SimAnticsError.unsupported(let reason) {
            return ["unsupported at tick 0: \(reason)"]
        } catch {
            return ["error \(error)"]
        }
        func gap() -> String? {
            Self.firstGap(in: vm.reportedErrors.map { ($0.objectID, $0.error) }) { vm.entity(id: $0)?.object.guid }
        }
        func brokenRule(at tick: Int) -> String? {
            guard checksRules, let broken = vm.brokenRules().first else { return nil }
            let guid = vm.entity(id: broken.objectID).map { String(format: "0x%08X", $0.object.guid) } ?? "0x00000000"
            return "broken at tick \(tick) by \(guid): \(broken.rule.rawValue): \(broken.detail)"
        }
        defer { coverage?.sites.formUnion(vm.coveredInstructions()) }
        if let gap = gap() { return ["unsupported at tick 0\(gap)"] }
        if let broken = brokenRule(at: 0) { return [broken] }
        var lines = [Self.digest(of: vm, tick: 0)]
        let checkEvery = max(1, Int(vm.clock.ticksPerMinute))
        if ticks > 0 {
            for tick in 1...ticks {
                vm.tick()
                if let gap = gap() {
                    lines.append("unsupported at tick \(tick)\(gap)")
                    break
                }
                if tick % checkEvery == 0 || tick == ticks, let broken = brokenRule(at: tick) {
                    lines.append(broken)
                    break
                }
                if (every > 0 && tick % every == 0) || tick == ticks { lines.append(Self.digest(of: vm, tick: tick)) }
            }
        }
        return lines
    }
}

/// The instructions lot runs reached (``LotRunner/lotRun(_:ticks:every:seed:sims:checksRules:coverage:leftOut:)``),
/// gathered across runs. A coverage file keeps one ``SimAntics/InstructionSite`` a line.
public final class Coverage {
    public var sites: Set<InstructionSite> = []

    public init(sites: Set<InstructionSite> = []) {
        self.sites = sites
    }

    /// Reads a coverage file's lines, skipping any that aren't sites.
    public convenience init(text: String) {
        self.init(sites: Set(text.split(separator: "\n").compactMap { InstructionSite(line: $0) }))
    }

    /// The coverage file's text, sorted.
    public var text: String { sites.sorted().map(\.description).joined(separator: "\n") + "\n" }
}
