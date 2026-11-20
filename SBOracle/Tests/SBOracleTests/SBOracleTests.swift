import Foundation
import Testing
import SimAntics
import TSOContent
@testable import SBOracleCore

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL

@Suite struct StudyTests {
    let candidates: [UInt32] = Array(1...100)

    @Test func aSeedGivesTheSameSampleAndUntestedObjectsComeFirst() {
        let first = Study.sample(candidates, count: 10, seed: 42, tested: [])
        #expect(first == Study.sample(candidates.reversed(), count: 10, seed: 42, tested: []))   // order-free
        #expect(first != Study.sample(candidates, count: 10, seed: 43, tested: []))
        #expect(Set(first).count == 10)
        // With 95 tested, the five untested come first.
        let tested = Set(candidates.filter { $0 > 5 })
        #expect(Set(Study.sample(candidates, count: 7, seed: 1, tested: tested).prefix(5)) == [1, 2, 3, 4, 5])
        #expect(Study.sample([1, 2], count: 10, seed: 1, tested: []).count == 2)
    }

    @Test func theLotIsAGridWithSeededFacingsAndNoObjectsOfItsOwn() throws {
        let base = try Blueprint(xml: Data(#"<house><size>20</size><objects><object guid="0x9"/></objects></house>"#.utf8))
        let objects: [UInt32] = Array(1...12)
        let lot = Study.lot(objects, on: base, seed: 7)
        // A 20-tile lot holds a 3 by 3 grid, every 4 tiles from tile 4; the rest are left off.
        #expect(lot.objects.map(\.guid) == Array(1...9))
        #expect(lot.objects.map(\.x) == [4, 8, 12, 4, 8, 12, 4, 8, 12])
        #expect(lot.objects.allSatisfy { $0.level == 1 && [0, 2, 4, 6].contains($0.dir) })
        #expect(lot == Study.lot(objects, on: base, seed: 7))
        #expect(lot.objects.map(\.dir) != Study.lot(objects, on: base, seed: 8).objects.map(\.dir))
    }

    @Test func aSeedPicksTheFloorPlan() {
        let picks = (UInt64(1)...40).map { Study.floorPlan(of: 3, seed: $0) }
        #expect(Set(picks) == [0, 1, 2])
        #expect(picks == (UInt64(1)...40).map { Study.floorPlan(of: 3, seed: $0) })
        #expect(Study.floorPlan(of: 1, seed: 9) == 0 && Study.floorPlan(of: 0, seed: 9) == 0)
    }

    @Test func shrinkingFindsTheObjectThatShowsAFinding() {
        let objects: [UInt32] = Array(1...32)
        let (culprit, runs) = Study.shrink(objects, maxRuns: 20) { $0.contains(23) }
        #expect(culprit == [23] && runs <= 10)
        // Two that show it only together: halving stops at the smallest set holding both.
        let pair = Study.shrink(objects, maxRuns: 20) { $0.contains(3) && $0.contains(30) }
        #expect(pair.objects.contains(3) && pair.objects.contains(30))
        // The run budget bounds it.
        #expect(Study.shrink(objects, maxRuns: 1) { $0.contains(32) }.runs == 1)
    }

    @Test func theLedgerReadsBackWhatItWrites() {
        var ledger = StudyLedger()
        ledger.record(0x4D4F_4301, name: "Mock Chair", result: "clean", seed: 9)
        ledger.record(0x4D4F_4301, name: "Mock Chair", result: "broken: tick 9000", seed: 10)
        ledger.record(0x2, name: "Tab\there", result: "unsupported: primitive 1", seed: 3)
        let read = StudyLedger(tsv: ledger.tsv)
        #expect(read.entries[0x4D4F_4301] == StudyLedger.Entry(name: "Mock Chair", lots: 2, result: "broken: tick 9000", seed: 10))
        #expect(read.entries[0x2]?.name == "Tab here")
        #expect(read.tested == [0x4D4F_4301, 0x2])
    }

    @Test func theRecordsAddUpToTheSummary() {
        let records = ["lot\t1\t32\tclean", "lot\t2\t32\tinconclusive\tevery object was set aside", "lot\t3\t32\tbroken\tbroken at tick 9000",
                       "shrunk\t3\t0x00000017\tbroken: broken at tick 9000", "object\t0x00000001\tclean",
                       "object\t0x00000017\tbroken\ton lot 3: slots", "object\t0x00000005\tunsupported\tprimitive 1 (generic_sims_online_call)",
                       "sims\t1\t2", "not a record"]
        let summary = StudySummary(records: records)
        #expect(summary.cleanLots == 1 && summary.cleanObjects == 1)
        #expect(summary.inconclusive == ["every object was set aside": 1])
        #expect(summary.findings == ["seed 3, objects 0x00000017: broken: broken at tick 9000"])
        #expect(summary.unsupported == ["primitive 1 (generic_sims_online_call)": 1])
        #expect(summary.lines.first == "Study: 1 lots clean, 1 with findings, 1 inconclusive; 1 objects clean, 1 set aside as unsupported")
        #expect(summary.lines.count == 2)
    }

    @Test func theDefaultFloorPlanIsAnEmptyLot() throws {
        let lot = try Study.emptyLot()
        #expect(lot.size == 77 && lot.objects.isEmpty && lot.walls.isEmpty && lot.floors.isEmpty)
        #expect(Study.lot([1, 2, 3], on: lot, seed: 1).objects.count == 3)
    }

    @Test func theWeightedSampleRepeatsFromItsSeedAndFavorsHeavyObjects() {
        let candidates = Array(UInt32(1)...200)
        let weights = Dictionary(uniqueKeysWithValues: candidates.map { ($0, $0 <= 20 ? 50.0 : 1.0) })
        let first = Study.sample(candidates, count: 20, seed: 7, weights: weights)
        #expect(first == Study.sample(candidates.reversed(), count: 20, seed: 7, weights: weights))
        #expect(first.count == 20 && Set(first).count == 20)
        // The 20 heavy candidates are a tenth of them, but most of the picks.
        var heavy = 0
        for seed in UInt64(0)..<50 { heavy += Study.sample(candidates, count: 20, seed: seed, weights: weights).filter { $0 <= 20 }.count }
        #expect(heavy > 50 * 20 / 2)
        // Untested candidates still come first, whatever their weight.
        let tested = Set(UInt32(1)...190)
        #expect(Set(Study.sample(candidates, count: 10, seed: 7, weights: weights, tested: tested)) == Set(UInt32(191)...200))
        #expect(Study.sample(candidates, count: 0, seed: 7, weights: weights).isEmpty)
    }

    @Test func coverageWeightsShrinkWithLotsAndNeverFallBelowOne() {
        #expect(Study.coverageWeight(uncovered: 0, lots: 0) == 1)
        #expect(Study.coverageWeight(uncovered: 100, lots: 0) == 101)
        #expect(Study.coverageWeight(uncovered: 100, lots: 4) == 21)
        #expect(Study.coverageWeight(uncovered: -5, lots: -1) == 1)
    }

    @Test func simsComeFromTheirOwnStreamAndStandInWhenHalving() {
        let counts = (UInt64(0)..<100).map { Study.simCount(most: 3, seed: $0) }
        #expect(counts.allSatisfy { (0...3).contains($0) } && Set(counts) == [0, 1, 2, 3])
        #expect(Study.simCount(most: 0, seed: 9) == 0)
        let tokens = Study.simTokens(3)
        #expect(tokens.count == 3 && tokens.allSatisfy(Study.isSimToken) && !Study.isSimToken(0x7FD9_6B54))
    }

    @Test func coverageFilesReadBackAndSkipOtherLines() {
        let coverage = Coverage(text: "global\t256\t0\nnot a site\nobject a.iff\t4096\t3\n")
        #expect(coverage.sites == [InstructionSite(file: "global", routine: 256, index: 0),
                                   InstructionSite(file: "object a.iff", routine: 4096, index: 3)])
        #expect(Coverage(text: coverage.text).sites == coverage.sites)
    }

    /// Unrepeatable runs are findings too, listed by their halved set.
    @Test func unrepeatableRunsAreFindings() {
        let records = ["lot\t5\t32\tunrepeatable\ttwo runs of the same seed differ",
                       "shrunk\t5\t0x00000018\tunrepeatable: two runs", "object\t0x00000018\tunrepeatable\ton lot 5: two runs"]
        let summary = StudySummary(records: records)
        #expect(summary.cleanLots == 0 && summary.inconclusive.isEmpty)
        #expect(summary.findings == ["seed 5, objects 0x00000018: unrepeatable: two runs"])
    }

    /// A lot run names the object that reached something unsupported first; other errors don't count.
    @Test func aLotRunNamesTheObjectThatReachedSomethingUnsupported() {
        let reported: [(objectID: Int16, error: SimAnticsError)] = [
            (3, .indexOutOfRange("motive 16")), (7, .unsupported("primitive 13 (push_interaction)")), (8, .unsupported("later")),
        ]
        #expect(LotRunner.firstGap(in: reported) { $0 == 7 ? 0x7FD9_6B54 : nil } == " by 0x7FD96B54: primitive 13 (push_interaction)")
        #expect(LotRunner.firstGap(in: reported) { _ in nil } == ": primitive 13 (push_interaction)")
        #expect(LotRunner.firstGap(in: [(1, .infiniteLoop)]) { _ in 1 } == nil)
    }

    /// The mock Sim joins its lot, then runs with its motives decaying: nothing on the lot is
    /// unsupported any more.
    @Test func theMockSimsLotRunsWithItsSim() throws {
        let mock = repository.appendingPathComponent("MockInstall")
        let content = try GameContent(.init(gameDirectory: mock.appendingPathComponent("TSOClient")))
        let lot = try Blueprint(xml: try Data(contentsOf: mock.appendingPathComponent("Lots/mock-lot-sim.xml")))
        let lines = LotRunner(content: content).lotRun(lot, ticks: 30, every: 10, sims: LotRunner.Sims(count: 1, template: 0x4D4F_4307))
        #expect(lines.map { $0.split(separator: " ").prefix(2).joined(separator: " ") } == ["tick 0", "tick 10", "tick 20", "tick 30"],
                "\(lines.suffix(2))")
        // Checking the lot's rules over a game hour breaks none and changes no digest.
        let answers = LotRunner(content: content)
        let sims = LotRunner.Sims(count: 1, template: 0x4D4F_4307)
        let checked = answers.lotRun(lot, ticks: 9_000, every: 1_500, sims: sims, checksRules: true)
        #expect(checked == answers.lotRun(lot, ticks: 9_000, every: 1_500, sims: sims), "\(checked.suffix(1))")
    }
}
