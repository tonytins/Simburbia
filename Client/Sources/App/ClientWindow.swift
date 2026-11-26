import Foundation
import Hudini
import Raylib

/// The client's one window, opened before anything loads so the loading screen shows at once,
/// and the interface's look, which needs the window: the fonts the interface's appearance names
/// (`Interface/appearance.xml`) load once it's open and unload before it closes.
enum ClientWindow {
    /// The interface's look while the window is open: Hudini's standard palette with the
    /// appearance's fonts, or without them before the window opens or if they couldn't be
    /// loaded. Set and read only on the main thread, which owns the window.
    nonisolated(unsafe) private(set) static var theme = InterfaceTheme.standard
    /// The fonts loaded so far, by the file and size they were loaded from, so each loads once.
    nonisolated(unsafe) private static var fonts: [UIScript.FontResource: Font] = [:]

    /// Opens it, hidden when the client only takes a screenshot, and fills the theme with the
    /// fonts `appearance`'s `<Fonts>` names. Returns why a font couldn't be loaded, if one
    /// couldn't; its text then draws in raylib's own font.
    static func open(hidden: Bool, appearance: Appearance, simburbiaFolder: URL) -> [String] {
        SetTraceLogLevel(.warning)
        SetConfigFlags(hidden ? [.windowHidden] : [.windowResizable, .vsyncHint, .msaa4xHint])
        InitWindow(1280, 720, "Simburbia")
        SetTargetFPS(60)
        // Escape closes the lot's windows instead of the client.
        SetExitKey(.null)

        var warnings: [String] = []
        theme = InterfaceTheme.standard.withFonts(from: appearance) { resource in
            if let font = fonts[resource] { return font }
            let path = InterfaceDocuments.url(ofAppearancePath: resource.path, in: simburbiaFolder).path
            guard FileManager.default.fileExists(atPath: path) else {
                warnings.append("Interface/\(resource.path) is missing, so its text uses raylib's font")
                return nil
            }
            let font = LoadFontEx(path, Int32(resource.size), latin1, Int32(latin1.count))
            guard IsFontValid(font) else {
                warnings.append("Interface/\(resource.path) couldn't be read, so its text uses raylib's font")
                return nil
            }
            SetTextureFilter(font.texture, .bilinear)
            fonts[resource] = font
            return font
        }
        return warnings
    }

    /// Unloads the fonts, then closes the window.
    static func close() {
        theme = .standard
        for font in fonts.values { UnloadFont(font) }
        fonts = [:]
        CloseWindow()
    }

    /// The characters each font is loaded with: printable ASCII and Latin-1, which TSO's text uses
    /// (such as "©" and accented names).
    private static let latin1: [Int32] = Array(32...126) + Array(160...255)
}
