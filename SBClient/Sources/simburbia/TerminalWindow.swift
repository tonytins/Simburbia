import Hudini
import LotScene
import Raylib
import SimAntics

/// The drop-down terminal (`Interface/terminal.xml`), opened and closed with Ctrl+Shift+C: a
/// window in Hudini's ``WindowManager`` whose input runs ``TerminalCommands`` on the lot.
final class TerminalWindow {
    /// How many lines the output keeps, oldest dropped first.
    static let keptLines = 500

    private let windows: WindowManager
    private let frame: WindowFrame
    private let view: UIView
    private let width: Float
    private let vm: VM
    private var commands = TerminalCommands()
    private var lines = ["Simburbia's terminal. Type help for the commands."]

    init(script: UIScript, vm: VM, windows: WindowManager) {
        self.windows = windows
        self.vm = vm
        view = UIView(script: script, theme: .simburbia)
        frame = WindowFrame(view: view, title: "Terminal")
        width = script.window.size.width
        view.list(named: "output")?.items = lines
    }

    var isOpen: Bool { windows.isOpen(frame) }

    /// Whether the keyboard belongs to the terminal: it's open with its input focused, so the
    /// game's keys must wait.
    var isTyping: Bool { isOpen && view.textField(named: "input")?.isFocused == true }

    /// Whether Ctrl+Shift+C was pressed this frame.
    static var togglePressed: Bool {
        (IsKeyDown(.leftControl) || IsKeyDown(.rightControl)) && (IsKeyDown(.leftShift) || IsKeyDown(.rightShift))
            && IsKeyPressed(.c)
    }

    /// Opens the terminal under the top bar, centered, with its input focused, or closes it.
    func toggle() {
        if isOpen {
            close()
            return
        }
        let start = Vector2(x: ((Float(GetScreenWidth()) - width) / 2).rounded(), y: 34)
        windows.open(frame, at: start) { [unowned self] event in handle(event) }
        view.textField(named: "input")?.setFocused(true)
    }

    func close() {
        view.clearFocus()
        windows.close(frame)
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
        view.list(named: "output")?.items = lines
    }

    private func handle(_ event: WindowFrame.Event) {
        switch event {
        case .closeRequested:
            close()
        case .view(.submitted(control: "input", let text)):
            submit(text)
        default:
            break
        }
    }
}
