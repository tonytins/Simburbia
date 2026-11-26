import Foundation
import Hudini
import TSOContent
import TSOFiles

/// Where the interface's images come from: TSO's graphics by asset ID, from the install's
/// `uigraphics`, and Simburbia's own by path, from the `Interface` folder.
///
/// An `<Image>` with both tries its asset ID first, since TSO's art is the look Simburbia is
/// after, and its path when the install doesn't have it. With neither found, Hudini draws the
/// control from the theme.
struct InterfaceArt: Sendable {
    /// The install's interface graphics, or `nil` without an install.
    let graphics: UIGraphicsProvider?
    let simburbiaFolder: URL

    /// Opens the install's interface graphics, if `gameDirectory` lists. An archive that doesn't
    /// read is returned as a warning, and the others still load.
    static func open(gameDirectory: URL, simburbiaFolder: URL) -> (InterfaceArt, warnings: [String]) {
        guard let files = try? GameFileIndex(root: gameDirectory) else {
            return (InterfaceArt(graphics: nil, simburbiaFolder: simburbiaFolder), [])
        }
        let graphics = UIGraphicsProvider(files: files)
        let warnings = graphics.failures.map { "the interface graphics in \($0.path) can't be read: \($0.reason)" }
        return (InterfaceArt(graphics: graphics, simburbiaFolder: simburbiaFolder), warnings)
    }

    /// Where an image comes from.
    enum Source {
        /// One of the install's graphics, decoded.
        case graphic(RasterImage)
        /// A file in the `Interface` folder, for raylib to load.
        case file(URL)
    }

    /// Finds `resource`'s image, and says why for each way it couldn't. `nil` with no warnings is
    /// an asset ID without an install: expected, so the control is drawn from the theme quietly.
    func source(for resource: UIScript.ImageResource) -> (Source?, warnings: [String]) {
        var warnings: [String] = []
        if let text = resource.assetID {
            if let id = Self.assetID(text) {
                if let graphics {
                    do {
                        if let image = try graphics.image(id: id) { return (.graphic(image), warnings) }
                        warnings.append("the install has no interface graphic \(text)")
                    } catch {
                        warnings.append("the interface graphic \(text) can't be read: \(error)")
                    }
                }
            } else {
                warnings.append("'\(text)' isn't an asset ID: 0x and up to 16 hex digits")
            }
        }
        if let path = resource.path {
            let url = InterfaceDocuments.url(ofInterfacePath: path, in: simburbiaFolder)
            if FileManager.default.fileExists(atPath: url.path) { return (.file(url), []) }
            warnings.append("Interface/\(path) is missing")
        }
        return (nil, warnings)
    }

    /// An asset ID as documents write it, TSO's `.uis` files among them: `0x`, then the file ID
    /// and the type ID packed as up to 16 hex digits (`0x0000088500000001`). `nil` for anything
    /// else.
    static func assetID(_ text: String) -> AssetID? {
        guard text.hasPrefix("0x") || text.hasPrefix("0X") else { return nil }
        let digits = text.dropFirst(2)
        guard (1...16).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let packed = UInt64(digits, radix: 16) else { return nil }
        return AssetID(packed: packed)
    }
}
