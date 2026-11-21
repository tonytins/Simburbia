import Hudini
import Raylib

/// A window whose content is a UIScript document, in the client's ``WindowManager``: Hudini's
/// frame around the document's view. The manager stacks the windows, gives the front one the
/// input, and draws them; this opens and closes it.
final class ManagedWindow {
    let frame: WindowFrame
    let view: UIView
    private let windows: WindowManager
    private let start: () -> Vector2
    /// The window's events besides closing, such as a submitted text field.
    var onEvent: (WindowFrame.Event) -> Void = { _ in }

    /// - Parameters:
    ///   - start: where the window's top left goes when it opens, worked out then, from the screen
    ///     as it is.
    init(title: String, script: UIScript, in windows: WindowManager, start: @escaping () -> Vector2) {
        view = UIView(script: script, theme: .simburbia)
        frame = WindowFrame(view: view, title: title)
        self.windows = windows
        self.start = start
    }

    var isOpen: Bool { windows.isOpen(frame) }

    /// Opens the window at its start, in front, or brings it to the front if it's open.
    func open() {
        guard !isOpen else {
            windows.bringToFront(frame)
            return
        }
        windows.open(frame, at: start()) { [unowned self] event in
            if event == .closeRequested {
                close()
            } else {
                onEvent(event)
            }
        }
    }

    func close() {
        view.clearFocus()
        windows.close(frame)
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }
}
