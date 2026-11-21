import Foundation
import Hudini
import Raylib

/// The client's one window, opened before anything loads so the loading screen shows at once,
/// and the interface's look, which needs the window: its fonts load once it's open and unload
/// before it closes.
enum ClientWindow {
    /// The size each font is loaded at, in pixels: twice the interface's usual 14 and 16, so text
    /// scales down from it smoothly.
    static let fontSize = 32

    /// The interface's look while the window is open: Simburbia's colors with its fonts, or
    /// without them before the window opens or if they couldn't be loaded. Set and read only on
    /// the main thread, which owns the window.
    nonisolated(unsafe) private(set) static var theme = InterfaceTheme.standard
    nonisolated(unsafe) private static var fonts: [Font] = []

    /// Opens it, hidden when the client only takes a screenshot, and loads the interface's fonts
    /// from `Interface/fonts`: Comic Neue for the interface, and Fira Mono for fixed-width text such
    /// as the terminal. Returns why a font couldn't be loaded, if one couldn't; its text then draws
    /// in raylib's own font.
    static func open(hidden: Bool, simburbiaFolder: URL) -> [String] {
        SetTraceLogLevel(.warning)
        SetConfigFlags(hidden ? [.windowHidden] : [.windowResizable, .vsyncHint, .msaa4xHint])
        InitWindow(1280, 720, "Simburbia")
        SetTargetFPS(60)
        // Escape closes the lot's windows instead of the client.
        SetExitKey(.null)

        let folder = simburbiaFolder.appendingPathComponent("Interface/fonts", isDirectory: true)
        var warnings: [String] = []
        func load(_ file: String) -> Font? {
            let path = folder.appendingPathComponent(file).path
            guard FileManager.default.fileExists(atPath: path) else {
                warnings.append("Interface/fonts/\(file) is missing, so its text uses raylib's font")
                return nil
            }
            let font = LoadFontEx(path, Int32(fontSize), latin1, Int32(latin1.count))
            guard IsFontValid(font) else {
                warnings.append("Interface/fonts/\(file) couldn't be read, so its text uses raylib's font")
                return nil
            }
            SetTextureFilter(font.texture, .bilinear)
            fonts.append(font)
            return font
        }
        theme = InterfaceTheme(font: load("ComicNeue-Regular.ttf"), monospaceFont: load("FiraMono-Regular.ttf"))
        return warnings
    }

    /// Unloads the fonts, then closes the window.
    static func close() {
        theme = .standard
        for font in fonts { UnloadFont(font) }
        fonts = []
        CloseWindow()
    }

    /// The characters each font is loaded with: printable ASCII and Latin-1, which TSO's text uses
    /// (such as "©" and accented names).
    private static let latin1: [Int32] = Array(32...126) + Array(160...255)
}
