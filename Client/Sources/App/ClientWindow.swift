import Foundation
import Hudini
import Raylib

/// The client's one window, opened before anything loads so the loading screen shows at once,
/// and what the interface draws with, which needs the window: the fonts the interface's
/// appearance names (`Interface/appearance.xml`) and the images its documents name, loaded once
/// each while it's open and unloaded before it closes.
enum ClientWindow {
    /// The interface's look while the window is open: Hudini's standard palette with the
    /// appearance's fonts, or without them before the window opens or if they couldn't be
    /// loaded. Set and read only on the main thread, which owns the window, as is all of this.
    nonisolated(unsafe) private(set) static var theme = InterfaceTheme.standard
    /// Where images come from while the window is open.
    nonisolated(unsafe) private static var art: InterfaceArt?
    /// The fonts asked for so far, by the file and size they're loaded from, `nil` for one that
    /// couldn't be loaded, so each loads once and a missing one is reported once.
    nonisolated(unsafe) private static var fonts: [UIScript.FontResource: Font?] = [:]
    /// The images asked for so far, by asset ID and path, `nil` for one that couldn't be loaded,
    /// so each loads once and a missing one is reported once.
    nonisolated(unsafe) private static var images: [ImageKey: Texture2D?] = [:]

    private struct ImageKey: Hashable {
        let assetID: String?
        let path: String?
    }

    /// Opens it, hidden when the client only takes a screenshot, and fills the theme with the
    /// fonts `appearance`'s `<Fonts>` names. Returns why a font couldn't be loaded, if one
    /// couldn't; its text then draws in raylib's own font.
    static func open(hidden: Bool, appearance: Appearance, art: InterfaceArt) -> [String] {
        SetTraceLogLevel(.warning)
        SetConfigFlags(hidden ? [.windowHidden] : [.windowResizable, .vsyncHint, .msaa4xHint])
        InitWindow(1280, 720, "Simburbia")
        SetTargetFPS(60)
        // Escape closes the lot's windows instead of the client.
        SetExitKey(.null)

        self.art = art
        var warnings: [String] = []
        theme = InterfaceTheme.standard.withFonts(from: appearance) { resource in
            let (font, warning) = font(for: resource)
            if let warning { warnings.append(warning) }
            return font
        }
        return warnings
    }

    /// A font an appearance names, loaded once, for a `UIView`'s `loadFont`. A font that can't be
    /// loaded is reported on standard error, and its text draws in the theme's font.
    static func loadFont(_ resource: UIScript.FontResource) -> Font? {
        let (font, warning) = font(for: resource)
        if let warning { report(warning) }
        return font
    }

    /// An image a document names, loaded once, for a `UIView`'s `loadImage` (see
    /// ``InterfaceArt``). One that can't be loaded is reported on standard error, once, and its
    /// control draws from the theme.
    static func loadImage(_ resource: UIScript.ImageResource) -> Texture2D? {
        let key = ImageKey(assetID: resource.assetID, path: resource.path)
        if let texture = images[key] { return texture }
        guard let art else { return nil }
        let (source, warnings) = art.source(for: resource)
        var texture: Texture2D?
        switch source {
        case .graphic(let image):
            texture = image.makeTexture()
            if texture == nil { report("the interface graphic \(resource.assetID ?? "") can't be made a texture") }
        case .file(let url):
            let loaded = LoadTexture(url.path)
            if IsTextureValid(loaded) {
                SetTextureFilter(loaded, .bilinear)
                texture = loaded
            } else {
                report("Interface/\(resource.path ?? "") can't be read as an image")
            }
        case nil:
            break
        }
        // A path that loaded makes the asset ID's problems moot; otherwise each is worth knowing.
        if texture == nil { warnings.forEach(report) }
        images[key] = texture
        return texture
    }

    /// Unloads the images and fonts, then closes the window.
    static func close() {
        theme = .standard
        art = nil
        for case let texture? in images.values { UnloadTexture(texture) }
        images = [:]
        for case let font? in fonts.values { UnloadFont(font) }
        fonts = [:]
        CloseWindow()
    }

    private static func font(for resource: UIScript.FontResource) -> (Font?, warning: String?) {
        if let font = fonts[resource] { return (font, nil) }
        guard let art else { return (nil, nil) }
        let path = InterfaceDocuments.url(ofInterfacePath: resource.path, in: art.simburbiaFolder).path
        guard FileManager.default.fileExists(atPath: path) else {
            fonts[resource] = .some(nil)
            return (nil, "Interface/\(resource.path) is missing, so its text uses raylib's font")
        }
        let font = LoadFontEx(path, Int32(resource.size), latin1, Int32(latin1.count))
        guard IsFontValid(font) else {
            fonts[resource] = .some(nil)
            return (nil, "Interface/\(resource.path) couldn't be read, so its text uses raylib's font")
        }
        SetTextureFilter(font.texture, .bilinear)
        fonts[resource] = font
        return (font, nil)
    }

    private static func report(_ warning: String) {
        FileHandle.standardError.write(Data("simburbia: \(warning)\n".utf8))
    }

    /// The characters each font is loaded with: printable ASCII and Latin-1, which TSO's text uses
    /// (such as "©" and accented names).
    private static let latin1: [Int32] = Array(32...126) + Array(160...255)
}
