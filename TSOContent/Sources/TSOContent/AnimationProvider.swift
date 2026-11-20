import Foundation
import TSOFiles

/// Sims' animations, by file name: every `.anim` entry of the FAR3 archives under `animations`.
///
/// Ports FreeSO's `AvatarAnimationProvider` and the `FAR3Provider` it builds on. Names match in
/// any letter case, with the `.anim` extension (`a2o-standing-loop.anim`), as the VM asks for
/// them. Where two entries share a name, the later archive's wins, as FreeSO's indexer leaves
/// it; the names are listed in ``duplicates``. An archive that doesn't read is listed in
/// ``failures`` and the others still load.
///
/// Animations decode when asked for and aren't kept; a caller that asks often keeps its own.
public struct AnimationProvider: Sendable {
    private let archives: [FAR3Archive]
    private let paths: [String]
    private let entriesByName: [String: (archive: Int, entry: FAR3Archive.Entry)]

    /// Lower-case names found in more than one entry, each kept from the last.
    public let duplicates: [String]
    /// Archives that couldn't be read, each with why.
    public let failures: [BuildContentFailure]

    /// Opens every archive whose path holds `/animations/` and then `.dat`, in path order
    /// (FreeSO's unanchored `.*/animations/.*\.dat`, here in any letter case).
    public init(files: GameFileIndex) {
        var archives: [FAR3Archive] = [], paths: [String] = []
        var entriesByName: [String: (archive: Int, entry: FAR3Archive.Entry)] = [:]
        var duplicates: Set<String> = [], failures: [BuildContentFailure] = []
        for path in files.paths(where: Self.isArchive) {
            guard let url = files.url(for: path) else { continue }
            do {
                let archive = try FAR3Archive(contentsOf: url)
                for entry in archive.entries where entry.fileName.lowercased().hasSuffix(".anim") {
                    let name = entry.fileName.lowercased()
                    if entriesByName[name] != nil { duplicates.insert(name) }
                    entriesByName[name] = (archives.count, entry)
                }
                archives.append(archive)
                paths.append(path)
            } catch {
                failures.append(BuildContentFailure(path: path, reason: String(describing: error)))
            }
        }
        self.archives = archives
        self.paths = paths
        self.entriesByName = entriesByName
        self.duplicates = duplicates.sorted()
        self.failures = failures
    }

    static func isArchive(_ lowerCasePath: String) -> Bool {
        guard let start = ("/" + lowerCasePath).range(of: "/animations/") else { return false }
        return ("/" + lowerCasePath)[start.upperBound...].contains(".dat")
    }

    /// Every animation's name, lower case, sorted.
    public var names: [String] {
        entriesByName.keys.sorted()
    }

    /// The animation with this file name, such as `a2o-standing-loop.anim`, in any letter case,
    /// or `nil` if there's none.
    ///
    /// - Throws: ``ContentError/invalidFile(path:reason:)`` if its entry can't be read or decoded.
    public func animation(named name: String) throws(ContentError) -> Animation? {
        guard let (index, entry) = entriesByName[name.lowercased()] else { return nil }
        let data: Data
        do {
            data = try archives[index].data(for: entry)
        } catch {
            throw .invalidFile(path: "\(paths[index])/\(entry.fileName)", reason: String(describing: error))
        }
        do {
            return try Animation(bytes: data)
        } catch {
            throw .invalidFile(path: "\(paths[index])/\(entry.fileName)", reason: String(describing: error))
        }
    }
}
