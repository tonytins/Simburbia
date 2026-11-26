@testable import simburbia
import Foundation
import Hudini
import Testing
import TSOContent
import TSOFiles

private let simburbiaFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// One of the loose graphics `UIGraphicsProvider` knows by ID, and where it lives in an install.
private let looseID = "0x0000CBFB00000001"
private let loosePath = "uigraphics/hints/hint_mechanicskill.bmp"

/// A 24-bit BMP two pixels wide and one high: red, then magenta, which TSO's art means as clear.
private let twoPixels: Data = {
    var bytes = [UInt8](repeating: 0, count: 54)
    func put32(_ value: Int, _ at: Int) {
        for i in 0..<4 { bytes[at + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }
    let pixels: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 0]  // BGR, BGR, padding to 4 bytes
    bytes[0] = 0x42; bytes[1] = 0x4D
    put32(54 + pixels.count, 2); put32(54, 10); put32(40, 14); put32(2, 18); put32(1, 22)
    bytes[26] = 1; bytes[28] = 24
    return Data(bytes + pixels)
}()

/// A made-up install holding only `files`, by path, deleted after `body`.
private func withInstall(_ files: [String: Data], _ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("simburbia-art-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    for (path, data) in files {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try body(root)
}

private func image(_ attributes: String) throws -> UIScript.ImageResource {
    let script = try UIScript(data: Data("<UIScript><Window width='10' height='10'/><Image name='art' \(attributes)/></UIScript>".utf8))
    return try #require(script.resources.images["art"])
}

@Test func assetIDsReadAsTSOsDocumentsWriteThem() {
    #expect(InterfaceArt.assetID("0x0000088500000001")?.packed == 0x0000_0885_0000_0001)
    #expect(InterfaceArt.assetID("0X3a300000001")?.packed == 0x3A3_0000_0001)
    #expect(InterfaceArt.assetID("0x1")?.packed == 1)
    for bad in ["", "0x", "885", "0x00000885000000011", "0xG1", "0x-1", "0x+1", "0x１"] {
        #expect(InterfaceArt.assetID(bad) == nil, "\(bad)")
    }
}

@Test func anAssetIDComesFromTheInstallsGraphics() throws {
    try withInstall([loosePath: twoPixels]) { install in
        let (art, warnings) = InterfaceArt.open(gameDirectory: install, simburbiaFolder: simburbiaFolder)
        #expect(warnings.isEmpty)
        let (source, sourceWarnings) = art.source(for: try image("assetID='\(looseID)' path='logo.png'"))
        guard case .graphic(let graphic)? = source else {
            Issue.record("expected the install's graphic, got \(String(describing: source))")
            return
        }
        #expect(sourceWarnings.isEmpty)
        #expect(graphic.width == 2 && graphic.height == 1)
        // The magenta pixel is clear, as in every interface bitmap.
        #expect(Array(graphic.rgba[4..<8]) == [0, 0, 0, 0])
    }
}

@Test func anAssetIDTheInstallLacksFallsBackToItsPath() throws {
    try withInstall([loosePath: twoPixels]) { install in
        let (art, _) = InterfaceArt.open(gameDirectory: install, simburbiaFolder: simburbiaFolder)
        let (source, warnings) = art.source(for: try image("assetID='0x0000000100000001' path='logo.png'"))
        guard case .file(let url)? = source else {
            Issue.record("expected Interface/logo.png, got \(String(describing: source))")
            return
        }
        #expect(url.lastPathComponent == "logo.png")
        #expect(warnings.isEmpty, "a path that's there makes the missing graphic moot")
        // Without a path, the missing graphic is reported.
        let (none, missing) = art.source(for: try image("assetID='0x0000000100000001'"))
        #expect(none == nil)
        #expect(missing == ["the install has no interface graphic 0x0000000100000001"])
    }
}

@Test func aCorruptGraphicIsReportedNotTrapped() throws {
    try withInstall([loosePath: Data(twoPixels.prefix(60))]) { install in
        let (art, _) = InterfaceArt.open(gameDirectory: install, simburbiaFolder: simburbiaFolder)
        let (source, warnings) = art.source(for: try image("assetID='\(looseID)'"))
        #expect(source == nil)
        #expect(warnings.count == 1 && warnings[0].hasPrefix("the interface graphic \(looseID) can't be read"))
    }
}

@Test func withoutAnInstallAnAssetIDQuietlyDrawsFromTheTheme() throws {
    let art = InterfaceArt(graphics: nil, simburbiaFolder: simburbiaFolder)
    let (source, warnings) = art.source(for: try image("assetID='\(looseID)'"))
    #expect(source == nil)
    #expect(warnings.isEmpty)
}

@Test func badAssetIDsAndMissingPathsAreReported() throws {
    let art = InterfaceArt(graphics: nil, simburbiaFolder: simburbiaFolder)
    let (source, warnings) = art.source(for: try image("assetID='setup' path='no/such.png'"))
    #expect(source == nil)
    #expect(warnings == ["'setup' isn't an asset ID: 0x and up to 16 hex digits", "Interface/no/such.png is missing"])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["TSO_GAME_DIR"] != nil, "needs TSO_GAME_DIR"))
func setupComesFromARealInstallByItsAssetID() throws {
    let install = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TSO_GAME_DIR"]))
    let (art, warnings) = InterfaceArt.open(gameDirectory: install, simburbiaFolder: simburbiaFolder)
    #expect(warnings.isEmpty)
    let (source, sourceWarnings) = art.source(for: try image("assetID='\(LoadingScreen.setupID)'"))
    guard case .graphic(let setup)? = source else {
        Issue.record("expected setup from the install: \(sourceWarnings)")
        return
    }
    #expect(setup.width > 0 && setup.height > 0)
}
