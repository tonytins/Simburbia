import ArgumentParser
import Foundation
import SBOracleCore
import SimAntics
import TSOContent
import TSOFiles

/// `sb-oracle study`: the randomized study (`Study`), run on Simburbia for a time budget.
struct StudyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "study",
        abstract: "Sample objects onto lots, run each lot a game day on Simburbia, and check what happens.",
        discussion: """
            Until --minutes have passed, each lot takes --objects of the install's objects that \
            Simburbia loads (no person objects, no multi-tile parts but their lead), picked by its seed with the \
            objects whose code can reach instructions no run has reached yet likelier (--coverage-file), \
            and lays them on a grid of an emptied lot. Up to --sims visitor Sims join it, with no \
            owner on the lot; halving takes Sims out as well as objects. An object that reaches \
            something Simburbia doesn't support yet is recorded and set aside, and the lot runs again \
            without it. Each lot's rules (LotRule) are checked every game minute, and the lot runs \
            twice: a broken rule, or two runs that differ, is a finding, halved to the fewest objects \
            that still show it. A lot with neither is clean. The records go to --out/study.tsv.
            """)

    @OptionGroup var install: InstallOptions

    @Option(help: "The folder for the study's records.")
    var out: String

    @Option(help: "The ledger of each object's latest result, read and updated (such as docs/results/sb-study-ledger.tsv).")
    var ledger: String?

    @Option(help: "How long to sample lots for, in minutes; the lot under way when it runs out is finished.")
    var minutes: Double = 5

    @Option(help: "The first lot's seed, in decimal; each lot after adds one (default: the time now, recorded).")
    var seed: UInt64?

    @Option(help: "Objects on each lot.")
    var objects = Study.objectsPerLot

    @Option(name: .customLong("floor-plan"), help: """
        A lot whose walls and floors a sample may go on, its own objects taken out; each lot's seed \
        picks one. Repeatable (default: an empty lot, 77 tiles a side).
        """)
    var floorPlans: [String] = []

    @Option(help: """
        Instructions reached so far, one a line (file, routine, index), read and updated (such as \
        --out's coverage.tsv); objects whose code can reach instructions it doesn't hold are picked first.
        """)
    var coverageFile: String?

    @Flag(help: "Sample as the study did before coverage: objects the ledger hasn't seen first, unweighted. For comparing the two.")
    var unweighted = false

    @Option(help: "The most visitor Sims joining each lot, picked by its seed; none joins if the install can't run one yet.")
    var sims = 2

    @Option(help: "The person object visitor Sims are made from, in hexadecimal (default: the template person).")
    var simTemplate = String(VM.templatePerson, radix: 16, uppercase: true)

    @Option(help: "Ticks each lot runs (a game day by default).") var ticks = 216_000
    @Option(help: "A digest every this many ticks (a game hour by default).") var every = 9_000

    /// The most runs halving a finding takes.
    static let shrinkRuns = 12
    /// The most visitor Sims a lot takes: TSO's 18 visitors (TSO-E's lot limits, 2007).
    static let mostSims = 18
    /// The most objects one lot sets aside before it's counted inconclusive.
    static let mostSetAside = 16

    func validate() throws {
        guard minutes > 0, minutes.isFinite else { throw ValidationError("--minutes takes a positive number") }
        guard objects > 0 else { throw ValidationError("--objects takes a positive number") }
        guard ticks > 0, every > 0 else { throw ValidationError("--ticks and --every take positive numbers") }
        guard (0...Self.mostSims).contains(sims) else { throw ValidationError("--sims takes 0 to \(Self.mostSims)") }
        guard UInt32(simTemplate, radix: 16) != nil else { throw ValidationError("--sim-template takes a GUID in hexadecimal") }
    }

    func run() async throws {
        let content = try await install.load()
        let runner = LotRunner(content: content)
        let outFolder = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)

        let candidates = Self.candidates(content)
        let leads = Self.leadParts(content)
        let plans = floorPlans.isEmpty ? [try Study.emptyLot()]
            : try floorPlans.map { try Blueprint(xml: try Data(contentsOf: URL(fileURLWithPath: $0))) }
        var book = (ledger.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }).map(StudyLedger.init(tsv:)) ?? StudyLedger()
        let firstSeed = seed ?? UInt64(Date().timeIntervalSince1970)
        guard let template = UInt32(simTemplate, radix: 16) else { throw ValidationError("--sim-template takes a GUID in hexadecimal") }

        // What each candidate's code can reach, and what runs have reached so far: the sample's weights.
        // Interactions are left out until Sims use objects (phase D): their code can't run yet.
        let reach = try Census.reach(content: content, guids: candidates, interactions: false)
        let coverage = Coverage(text: coverageFile.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? "")
        let coveredAtStart = coverage.sites.count
        let reachable = reach.sizes.values.reduce(0, +)

        print("study: \(candidates.count) objects to sample from, \(objects) a lot, first seed \(firstSeed), \(minutes) minutes")
        var records: [String] = []
        var mostSims = sims
        if mostSims > 0, let reason = simsCantJoin(plans.first, template: template, runner: runner) {
            print("study: no Sims on this install: \(reason)")
            records.append("sims\t-\t0\tset aside\t\(reason)")
            mostSims = 0
        }
        let deadline = Date().addingTimeInterval(minutes * 60)
        var lotSeed = firstSeed
        while Date() < deadline {
            defer { lotSeed &+= 1 }
            let counts = Census.Reach.coveredCounts(coverage.sites)
            let weights = Dictionary(uniqueKeysWithValues: candidates.map { guid in
                (guid, Study.coverageWeight(uncovered: reach.uncovered(guid, coveredCounts: counts), lots: book.entries[guid]?.lots ?? 0))
            })
            var sample = unweighted ? Study.sample(candidates, count: objects, seed: lotSeed, tested: book.tested)
                : Study.sample(candidates, count: objects, seed: lotSeed, weights: weights, tested: book.tested)
            guard !sample.isEmpty else { break }
            let base = plans[Study.floorPlan(of: plans.count, seed: lotSeed)]
            var simCount = Study.simCount(most: mostSims, seed: lotSeed)
            func sims(_ count: Int) -> LotRunner.Sims? { count > 0 ? LotRunner.Sims(count: count, template: template) : nil }

            // Set aside each object that reaches something Simburbia doesn't support yet, and run
            // the lot again without it.
            var lot = Study.lot(sample, on: base, seed: lotSeed)
            var ours = runner.lotRun(lot, ticks: ticks, every: every, sims: sims(simCount), checksRules: true)
            var inconclusive: String?
            var setAside = 0
            while let last = ours.last, last.hasPrefix("unsupported") {
                // A Sim that reaches something unsupported leaves the lot, and the objects stay.
                if simCount > 0, let (reached, reason) = Self.unsupported(last), reached == template {
                    records.append("sims\t\(lotSeed)\t\(simCount)\tset aside\t\(reason)")
                    simCount = 0
                    ours = runner.lotRun(lot, ticks: ticks, every: every, checksRules: true)
                    continue
                }
                // The object that reached it may be a part of a sampled multi-tile object, or one a
                // sampled object made; then halving the lot finds which.
                guard setAside < Self.mostSetAside, let (reached, reason) = Self.unsupported(last),
                      let guid = sample.contains(reached) ? reached
                        : leads[reached].flatMap({ sample.contains($0) ? $0 : nil })
                        ?? Self.culprit(of: reason, in: lot, sims: sims(simCount), runner: runner, ticks: ticks, every: every) else {
                    inconclusive = "reached something unsupported in an object it can't set aside: \(Self.reason(of: last))"
                    break
                }
                records.append("object\t\(String(format: "0x%08X", guid))\tunsupported\t\(reason)")
                book.record(guid, name: nameOf(guid, content), result: "unsupported: \(reason)", seed: lotSeed)
                sample.removeAll { $0 == guid }
                setAside += 1
                lot.objects.removeAll { $0.guid == guid }
                ours = runner.lotRun(lot, ticks: ticks, every: every, sims: sims(simCount), checksRules: true)
            }
            if inconclusive == nil, lot.objects.isEmpty { inconclusive = "every object was set aside" }
            if inconclusive == nil, let last = ours.last, last.hasPrefix("error") { inconclusive = last }
            if let inconclusive {
                records.append("lot\t\(lotSeed)\t\(lot.objects.count)\tinconclusive\t\(inconclusive)")
                print("lot \(lotSeed): inconclusive, \(inconclusive)")
                continue
            }
            if simCount > 0 { records.append("sims\t\(lotSeed)\t\(simCount)") }
            let withSims = simCount > 0 ? " with \(simCount) Sim\(simCount == 1 ? "" : "s")" : ""

            // What this lot's run reached, for the next lots' weights. A run that's kept repeats
            // the first, so recording the second costs nothing extra.
            let before = coverage.sites.count
            let again = runner.lotRun(lot, ticks: ticks, every: every, sims: sims(simCount), checksRules: true, coverage: coverage)
            let reachedNew = coverage.sites.count - before

            // A finding: a broken rule, or a second run that differs. Either is halved to the fewest
            // objects (and Sims) that still show it, keeping each object's tile and facing.
            let whole = lot, wholeSims = simCount
            func part(_ subset: [UInt32]) -> (Blueprint, LotRunner.Sims?) {
                var part = whole
                part.objects.removeAll { !subset.contains($0.guid) }
                return (part, sims(subset.filter(Study.isSimToken).count))
            }
            let items = whole.objects.map(\.guid) + Study.simTokens(wholeSims)
            let finding: (kind: String, first: String, shows: ([UInt32]) -> Bool)?
            if let last = ours.last, last.hasPrefix("broken") {
                finding = ("broken", last, { subset in
                    let (lot, sims) = part(subset)
                    return runner.lotRun(lot, ticks: ticks, every: every, sims: sims, checksRules: true).last?.hasPrefix("broken") == true
                })
            } else if again != ours {
                finding = ("unrepeatable", "two runs of the same seed differ", { subset in
                    let (lot, sims) = part(subset)
                    return runner.lotRun(lot, ticks: ticks, every: every, sims: sims)
                        != runner.lotRun(lot, ticks: ticks, every: every, sims: sims)
                })
            } else {
                finding = nil
            }
            guard let finding else {
                records.append("lot\t\(lotSeed)\t\(lot.objects.count)\tclean")
                for object in lot.objects {
                    records.append("object\t\(String(format: "0x%08X", object.guid))\tclean")
                    book.record(object.guid, name: nameOf(object.guid, content), result: "clean", seed: lotSeed)
                }
                print("lot \(lotSeed): \(lot.objects.count) objects\(withSims) clean, \(reachedNew) new instructions")
                continue
            }
            records.append("lot\t\(lotSeed)\t\(lot.objects.count)\t\(finding.kind)\t\(finding.first)")
            print("lot \(lotSeed)\(withSims): \(finding.kind), \(finding.first); narrowing it down")
            let (culprits, _) = Study.shrink(items, maxRuns: Self.shrinkRuns, shows: finding.shows)
            record(culprits, kind: finding.kind, first: finding.first, seed: lotSeed, records: &records, book: &book, content: content)
        }

        let recordsFile = outFolder.appendingPathComponent("study.tsv")
        try Data((records.joined(separator: "\n") + "\n").utf8).write(to: recordsFile)
        if let ledger { try Data(book.tsv.utf8).write(to: URL(fileURLWithPath: ledger)) }
        if let coverageFile { try Data(coverage.text.utf8).write(to: URL(fileURLWithPath: coverageFile)) }
        for line in StudySummary(records: records).lines { print(line) }
        let reachedOfReach = Census.Reach.coveredCounts(coverage.sites).reduce(0) { $0 + min($1.value, reach.sizes[$1.key] ?? 0) }
        print("Study: coverage: \(coverage.sites.count) instructions reached (\(coverage.sites.count - coveredAtStart) new this run); "
              + "\(reachedOfReach) of the \(reachable) the candidates' own code can reach")
    }

    /// Records what halving left: the `shrunk` line, then each object's result. Sims are
    /// named by their count, since they're interchangeable.
    private func record(_ culprits: [UInt32], kind: String, first: String, seed: UInt64,
                        records: inout [String], book: inout StudyLedger, content: GameContent) {
        let objects = culprits.filter { !Study.isSimToken($0) }
        let simsLeft = culprits.count - objects.count
        let names = objects.map { String(format: "0x%08X", $0) } + (simsLeft > 0 ? ["\(simsLeft) Sim\(simsLeft == 1 ? "" : "s")"] : [])
        records.append("shrunk\t\(seed)\t\(names.joined(separator: ","))\t\(kind): \(first)")
        for guid in objects {
            records.append("object\t\(String(format: "0x%08X", guid))\t\(kind)\ton lot \(seed): \(first)")
            book.record(guid, name: nameOf(guid, content), result: "\(kind): \(first)", seed: seed)
        }
        print("lot \(seed): narrowed to \(names.joined(separator: ", "))")
    }

    /// Why Sims can't join this install's lots yet, or `nil` if a Sim on an empty floor plan runs
    /// a game day: on a real install the template person reaches the interaction queue (phase D).
    private func simsCantJoin(_ plan: Blueprint?, template: UInt32, runner: LotRunner) -> String? {
        guard var empty = plan else { return "no floor plan" }
        guard let person = try? runner.content.objects.object(guid: template), person.definition.knownObjectType == .person else {
            return String(format: "no person object 0x%08X to make them from (--sim-template)", template)
        }
        empty.objects = []
        let ours = runner.lotRun(empty, ticks: ticks, every: every, sims: LotRunner.Sims(count: 1, template: template), checksRules: true)
        if let last = ours.last, !last.hasPrefix("tick") { return Self.reason(of: last) }
        return nil
    }

    private func nameOf(_ guid: UInt32, _ content: GameContent) -> String {
        content.objects.reference(guid: guid)?.name ?? String(format: "0x%08X", guid)
    }

    /// The objects a lot may hold: those Simburbia loads, but no Sims (they join as visitors) and
    /// no multi-tile part but the lead, which places the rest.
    static func candidates(_ content: GameContent) -> [UInt32] {
        content.objects.references.map(\.guid).filter { guid in
            guard let object = try? content.objects.object(guid: guid) else { return false }
            let definition = object.definition
            return definition.knownObjectType != .person && (definition.masterID == 0 || definition.subIndex == -1)
        }
    }

    /// Each multi-tile part's lead part, which a lot names: parts share the lead's IFF and group.
    static func leadParts(_ content: GameContent) -> [UInt32: UInt32] {
        let references = content.objects.references
        var leads: [String: UInt32] = [:]
        for reference in references where reference.group != 0 && reference.subIndex == -1 {
            leads["\(reference.fileName)/\(reference.group)"] = reference.guid
        }
        var result: [UInt32: UInt32] = [:]
        for reference in references where reference.group != 0 && reference.subIndex >= 0 {
            if let lead = leads["\(reference.fileName)/\(reference.group)"] { result[reference.guid] = lead }
        }
        return result
    }

    /// The one object of a lot that leads Simburbia to `reason`, found by halving the lot, or
    /// `nil` if it takes more than one.
    static func culprit(of reason: String, in lot: Blueprint, sims: LotRunner.Sims? = nil, runner: LotRunner,
                        ticks: Int, every: Int) -> UInt32? {
        let (found, _) = Study.shrink(lot.objects.map(\.guid), maxRuns: 12) { subset in
            var part = lot
            part.objects.removeAll { !subset.contains($0.guid) }
            guard let last = runner.lotRun(part, ticks: ticks, every: every, sims: sims).last, last.hasPrefix("unsupported") else { return false }
            return Self.reason(of: last) == reason
        }
        return found.count == 1 ? found.first : nil
    }

    /// The object and what it reached, from `unsupported at tick N by 0xGUID: what`.
    static func unsupported(_ line: String) -> (UInt32, String)? {
        guard let by = line.range(of: " by 0x"), let colon = line.range(of: ": ", range: by.upperBound..<line.endIndex),
              let guid = UInt32(line[by.upperBound..<colon.lowerBound], radix: 16) else { return nil }
        return (guid, String(line[colon.upperBound...]))
    }

    static func reason(of line: String) -> String {
        line.range(of: ": ").map { String(line[$0.upperBound...]) } ?? line
    }
}
