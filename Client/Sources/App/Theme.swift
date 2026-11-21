import Hudini
import Raylib

extension InterfaceTheme {
    /// Simburbia's interface look, the one place to change it: Hudini's standard palette, which
    /// NSOInterface's matched color for color, with Comic Neue and Fira Mono once the window has
    /// loaded them (``ClientWindow``).
    static var simburbia: InterfaceTheme { ClientWindow.theme }
}
