import Hudini
import Raylib
import SimAntics

/// The window that shows the selected object (`Interface/inspector.uix`): what it is, where,
/// and what it's running. It's open while an object is selected.
final class Inspector {
    let window: ManagedWindow
    private var shownLines: [String] = []

    init(script: UIScript, in windows: WindowManager) {
        let size = script.window.size
        window = ManagedWindow(title: "Object", script: script, in: windows) {
            Vector2(x: Float(GetScreenWidth()) - size.width - 20, y: 50)
        }
    }

    /// The object being inspected, by its ID in the VM; `nil` closes the window.
    var selected: Int16? {
        didSet {
            if selected == nil { window.close() } else { window.open() }
        }
    }

    func close() {
        selected = nil
    }

    /// Lets go of the selection when the window was closed some other way, such as its close
    /// button, or when the object is gone.
    func sync(with vm: VM) {
        if selected != nil, !window.isOpen || vm.entity(id: selected ?? 0) == nil { close() }
    }

    /// Fills the window from the object, before the windows are drawn.
    func show(_ entity: Entity) {
        let inspection = Inspection(entity)
        window.frame.title = inspection.title
        // The list wraps the lines, so it's refilled only when they change.
        if inspection.lines != shownLines {
            window.view.list(named: "lines")?.items = inspection.lines
            shownLines = inspection.lines
        }
    }
}
