import Foundation
import ScriptOracleCore
import SimAntics
import Testing

/// The repository's folder, which holds MockInstall.
private let simburbiaFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let mockInstall = simburbiaFolder.appendingPathComponent("MockInstall/TSOClient", isDirectory: true)

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("sso-tests-\(UUID().uuidString)", isDirectory: true)
}

private func run(_ scenarios: [Scenario]) throws -> [ScenarioResult] {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    return try ScenarioRunner(scenarios: scenarios).run(gameDirectory: mockInstall, lot: try ScenarioRunner.emptyLot(), objectFolder: folder)
}

@Suite struct ScenarioRunnerTests {
    @Test func everyBundledScenarioMeetsItsExpectations() throws {
        for result in try run(try ScenarioLibrary.bundled()) {
            #expect(result.passed, "\(result.recordLine) \(result.misses)")
        }
    }

    @Test func runsInitializeThenTheTicks() throws {
        let source = "integer ticks;\ndefault { initialize() { ticks = 100; } main() { ticks += 1; } }"
        let results = try run([try Scenario(name: "none", text: "// @ticks 0\n" + source),
                               try Scenario(name: "three", text: "// @ticks 3\n" + source)])
        #expect(results.map(\.recordLine) == ["none 5c000001 attributes ticks=100", "three 5c000002 attributes ticks=103"])
    }

    @Test func reportsAMissedExpectation() throws {
        let scenario = try Scenario(name: "wrong", text: "// @ticks 0\n// @expect a = 2\ninteger a;\ndefault { initialize() { a = 1; } }")
        let result = try #require(try run([scenario]).first)
        #expect(!result.passed)
        #expect(result.misses == [.init(attribute: "a", expected: 2, actual: 1)])
    }

    @Test func writesEachObjectAndTheTable() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let runner = ScenarioRunner(scenarios: try ScenarioLibrary.bundled())
        try runner.writeObjects(to: folder)
        let table = try String(contentsOf: folder.appendingPathComponent("scenarios.tsv"), encoding: .utf8)
        #expect(table == "5c000001\tarithmetic\t0\twrapped,divided,remainder,negative,masked\n5c000002\tcounting\t2\tcount\n")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("counting.iff").path))
    }

    @Test func stopsOnAScenarioThatDoesntCompile() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: ScenarioError.self) {
            try ScenarioRunner(scenarios: [try Scenario(name: "broken", text: "integer a; default { initialize() { a = ; } }")])
                .writeObjects(to: folder)
        }
    }
}
