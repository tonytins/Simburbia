import Foundation
import Hudini
import Raylib

/// The client's interface documents and the appearance they share, read once at start
/// (``InterfaceDocuments``).
struct Interface {
    let appearance: Appearance
    let topBar: UIScript
    let help: UIScript
    let momi: UIScript
    let inspector: UIScript
    let terminal: UIScript
    let loginStart: UIScript
    let loginJoin: UIScript

    /// Reads the appearance and every document from a Simburbia folder, each document with the
    /// appearance, and checks each has the controls the client uses. Attributes that Hudini
    /// ignored, such as a misspelled one, are returned as warnings.
    ///
    /// - Throws: ``Failure`` naming the appearance or document that's missing or doesn't read, or
    ///   the document that lacks a control.
    static func load(from simburbiaFolder: URL) throws -> (Interface, warnings: [String]) {
        var scripts: [String: UIScript] = [:]
        var warnings: [String] = []
        let appearanceURL = InterfaceDocuments.appearanceURL(in: simburbiaFolder)
        let appearance: Appearance
        do {
            appearance = try Appearance(contentsOf: appearanceURL)
        } catch {
            throw Failure(description: "couldn't read the interface's appearance \(appearanceURL.path): \(error.localizedDescription)")
        }
        warnings += appearance.ignoredAttributes.map { "appearance.xml line \($0.line): \($0.element) ignores '\($0.attribute)'" }
        for (document, controls) in InterfaceDocuments.required {
            let url = InterfaceDocuments.url(of: document, in: simburbiaFolder)
            let script: UIScript
            do {
                script = try UIScript(contentsOf: url, appearance: appearance)
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
        return (Interface(appearance: appearance, topBar: topBar, help: help, momi: momi, inspector: inspector, terminal: terminal,
                          loginStart: loginStart, loginJoin: loginJoin), warnings)
    }
}
