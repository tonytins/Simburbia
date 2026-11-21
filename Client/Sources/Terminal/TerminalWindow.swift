import Hudini
import Raylib
import SimAntics

/// The drop-down terminal (`Interface/terminal.uix`), opened and closed with Ctrl+Shift+C: a
/// window in Hudini's ``WindowManager`` whose input runs ``TerminalCommands`` on the lot.
final class TerminalWindow {
    /// How many lines the output keeps, oldest dropped first.
    static let keptLines = 500

    private let window: ManagedWindow
    private let vm: VM
    private var commands = TerminalCommands()
    private var lines = ["Simburbia's terminal. Type help for the commands."]

    init(script: UIScript, vm: VM, windows: WindowManager) {
        self.vm = vm
        let width = script.window.size.width
        window = ManagedWindow(title: "Terminal", script: script, in: windows) {
            // Under the top bar, centered.
            Vector2(x: ((Float(GetScreenWidth()) - width) / 2).rounded(), y: 34)
        }
        window.view.list(named: "output")?.items = lines
        window.onEvent = { [unowned self] event in
            if case .view(.submitted(control: "input", let text)) = event { submit(text) }
        }
    }

    var isOpen: Bool { window.isOpen }

    /// Whether the keyboard belongs to the terminal: it's open with its input focused, so the
    /// game's keys must wait.
    var isTyping: Bool { isOpen && window.view.textField(named: "input")?.isFocused == true }

    /// Whether Ctrl+Shift+C was pressed this frame.
    static var togglePressed: Bool {
        (IsKeyDown(.leftControl) || IsKeyDown(.rightControl)) && (IsKeyDown(.leftShift) || IsKeyDown(.rightShift))
            && IsKeyPressed(.c)
    }

    /// Opens the terminal under the top bar, centered, with its input focused, or closes it.
    func toggle() {
        if isOpen {
            close()
        } else {
            window.open()
            window.view.textField(named: "input")?.setFocused(true)
        }
    }

    func close() {
        window.close()
    }

    /// Runs a line as if it were typed and submitted.
    func submit(_ line: String) {
        lines.append("> " + line)
        let answer = commands.run(line, on: vm)
        if line.trimmingCharacters(in: .whitespaces).lowercased() == "clear" {
            lines = []
        } else {
            lines += answer
        }
        if lines.count > Self.keptLines { lines.removeFirst(lines.count - Self.keptLines) }
        window.view.list(named: "output")?.items = lines
    }
}
