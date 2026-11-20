import ArgumentParser
import Configuration
import Foundation
import SBOracleCore
import SimAntics
import TSOConfig
import TSOContent

/// `sb-oracle`: checks on Simburbia that need an install but no window, such as the randomized
/// study and the content census.
@main
struct SBOracle: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sb-oracle",
        abstract: "Check Simburbia against a TSO install: the randomized study and the content census.",
        subcommands: [StudyCommand.self, CensusCommand.self])
}

struct InstallOptions: ParsableArguments {
    @Option(help: "The TSO install. Defaults to $TSO_GAME_DIR.")
    var game: String?

    @Option(help: "A FreeSO-style content folder, for patches and standalone objects (default: $FSO_CONTENT_DIR, else none).")
    var content: String?

    func load() async throws -> GameContent {
        try GameContent(.init(gameDirectory: try gameDirectory(), freeSOContentDirectory: try contentDirectory()))
    }

    /// The install: `--game`, else `TSO_GAME_DIR`.
    func gameDirectory() throws -> URL {
        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        let directory = game.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? InstallKind.installs(in: config).first { $0.kind == .game }?.directory
        guard let directory, game?.isEmpty != true else {
            throw ValidationError("No --game given and TSO_GAME_DIR is not set.")
        }
        return directory
    }

    /// The content folder: `--content`, else `FSO_CONTENT_DIR`, else none.
    func contentDirectory() throws -> URL? {
        try FreeSOContentLocator(configuredDirectory: content.map { URL(fileURLWithPath: $0, isDirectory: true) },
                                 executableDirectory: nil).locate()
    }
}
