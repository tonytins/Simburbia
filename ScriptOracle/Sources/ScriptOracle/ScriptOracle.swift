import ArgumentParser
import Configuration
import Foundation
import ScriptOracleCore
import SimAntics
import TSOConfig
import TSOContent

/// `sso-oracle`: experiments written in SimsScript, run on Simburbia's VM.
@main
struct ScriptOracle: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sso-oracle",
        abstract: "Run experiments written in SimsScript.",
        discussion: """
            A scenario is a SimsScript object (.ss) with a header that says how long to run it and \
            which attributes it should leave. See ScriptOracle/README.md.
            """,
        subcommands: [Check.self, Build.self, Run.self])
}

/// Where the scenarios come from: a folder, or the ones that ship with sso-oracle.
struct ScenarioOptions: ParsableArguments {
    @Option(help: "A folder of .ss scenarios (default: the ones that ship with sso-oracle).")
    var scenarios: String?

    func load() throws -> [Scenario] {
        guard let scenarios else { return try ScenarioLibrary.bundled() }
        return try ScenarioLibrary.load(folder: URL(fileURLWithPath: scenarios, isDirectory: true))
    }
}

extension ScriptOracle {
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compile every scenario and check its header, without running anything.")
        @OptionGroup var options: ScenarioOptions

        func run() throws {
            var failed = 0
            for scenario in try options.load() {
                do {
                    let object = try scenario.compiled()
                    print("\(scenario.name) ok: \(object.routines.count) routines, \(scenario.ticks) ticks, "
                          + "\(scenario.expectations.count) expectations")
                } catch {
                    print("\(scenario.name) error: \(error)")
                    failed += 1
                }
            }
            if failed > 0 { throw ExitCode.failure }
        }
    }
}

/// The repository's folder, which holds MockInstall.
private let simburbiaFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

extension ScriptOracle {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compile every scenario into a folder of standalone objects.",
            discussion: """
                Writes NAME.iff for each scenario, a folder a content folder can hold as Objects, \
                and scenarios.tsv: each object's GUID, its scenario's name, and its ticks.
                """)
        @OptionGroup var options: ScenarioOptions
        @Argument(help: "The folder to write.") var folder: String

        func run() throws {
            let runner = ScenarioRunner(scenarios: try options.load())
            try runner.writeObjects(to: URL(fileURLWithPath: folder, isDirectory: true))
            print("wrote \(runner.scenarios.count) scenarios to \(folder)")
        }
    }

    /// Where Simburbia's VM runs the scenarios.
    struct RunOptions: ParsableArguments {
        @Option(help: "The TSO install to load (default: $TSO_GAME_DIR, else Simburbia's MockInstall).")
        var game: String?

        @Option(help: "The lot to run on; its objects are taken out (default: an empty lot, 77 tiles a side).")
        var blueprint: String?

        /// Runs the scenarios on Simburbia's VM.
        func results(of scenarios: [Scenario]) throws -> [ScenarioResult] {
            let installs = InstallKind.installs(in: ConfigReader(provider: EnvironmentVariablesProvider()))
            let game = game.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? installs.first { $0.kind == .game }?.directory
                ?? simburbiaFolder.appendingPathComponent("MockInstall/TSOClient", isDirectory: true)
            let lot = try blueprint.map { try Blueprint(xml: try Data(contentsOf: URL(fileURLWithPath: $0))) }
                ?? ScenarioRunner.emptyLot()
            let objects = FileManager.default.temporaryDirectory
                .appendingPathComponent("sso-oracle-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: objects) }
            return try ScenarioRunner(scenarios: scenarios).run(gameDirectory: game, lot: lot, objectFolder: objects)
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run every scenario on Simburbia's VM and check its expectations.",
            discussion: """
                Prints one record line per scenario (its object variables, then any errors), then \
                whether it met its expectations. Exits with 1 if any scenario missed one or hit an error.
                """)
        @OptionGroup var options: ScenarioOptions
        @OptionGroup var runOptions: RunOptions

        @Flag(help: "Print only the record lines.")
        var recordsOnly = false

        func run() throws {
            let results = try runOptions.results(of: try options.load())
            var failed = 0
            for result in results {
                print(result.recordLine)
                if !result.passed { failed += 1 }
                guard !recordsOnly else { continue }
                for miss in result.misses {
                    print("  missed: \(miss.attribute) is \(miss.actual), expected \(miss.expected)")
                }
                if result.passed { print("  ok") }
            }
            if !recordsOnly { print("\(results.count - failed) of \(results.count) scenarios passed") }
            if failed > 0 { throw ExitCode.failure }
        }
    }
}
