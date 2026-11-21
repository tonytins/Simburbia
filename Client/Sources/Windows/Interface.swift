import Foundation
import Hudini
import Raylib

/// The client's interface documents, read once at start (``InterfaceDocuments``).
struct Interface {
    let topBar: UIScript
    let help: UIScript
    let momi: UIScript
    let inspector: UIScript
    let terminal: UIScript
    let loginStart: UIScript
    let loginJoin: UIScript

    /// Reads every document from a Simburbia folder, and checks each has the controls the client
    /// uses. Attributes a document has that Hudini ignored, such as a misspelled one, are
    /// returned as warnings.
    ///
    /// - Throws: ``Failure`` naming the document that's missing, doesn't read, or lacks a control.
    static func load(from simburbiaFolder: URL) throws -> (Interface, warnings: [String]) {
        var scripts: [String: UIScript] = [:]
        var warnings: [String] = []
        for (document, controls) in InterfaceDocuments.required {
            let url = InterfaceDocuments.url(of: document, in: simburbiaFolder)
            let script: UIScript
            do {
                script = try UIScript(contentsOf: url)
            } catch {
                throw Failure(description: "couldn't read the interface document \(url.path): \(error.localizedDescription)")
            }
            let missing = controls.filter { script.control(named: $0) == nil }
            guard missing.isEmpty else {
                throw Failure(description: "the interface document \(url.path) has no control named \(missing.joined(separator: ", "))")
            }
            warnings += script.ignoredAttributes.map { "\(document).uix line \($0.line): \($0.element) ignores '\($0.attribute)'" }
            scripts[document] = script
        }
        guard let topBar = scripts["topbar"], let help = scripts["help"], let momi = scripts["momi"],
              let inspector = scripts["inspector"], let terminal = scripts["terminal"], let loginStart = scripts["login-start"],
              let loginJoin = scripts["login-join"] else {
            throw Failure(description: "the interface documents are incomplete")
        }
        return (Interface(topBar: topBar, help: help, momi: momi, inspector: inspector, terminal: terminal,
                          loginStart: loginStart, loginJoin: loginJoin), warnings)
    }
}
