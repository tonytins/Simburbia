import Hudini
import Raylib

extension InterfaceTheme {
    /// Simburbia's interface look: Hudini's standard palette, which NSOInterface's matched color
    /// for color, with the fonts `Interface/appearance.xml` names once the window has loaded them
    /// (``ClientWindow``).
    static var simburbia: InterfaceTheme { ClientWindow.theme }
}
