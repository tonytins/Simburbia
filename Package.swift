// swift-tools-version: 6.2

import PackageDescription

// The client, `simburbia`: `swift run simburbia` from the repository root. Its sources are in
// `Client/`, grouped by job. The libraries it uses are the packages beside it, each independent.
let package = Package(
    name: "Simburbia",
    // A tool, so it may require a newer macOS than the libraries: swift-configuration needs 15.
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "simburbia", targets: ["simburbia"]),
    ],
    dependencies: [
        .package(path: "TSOFiles"),
        .package(path: "TSOContent"),
        .package(path: "SimAntics"),
        // The owner's interface library, which NSOInterface grew into; it has no releases yet.
        .package(url: "https://github.com/tonytins/Hudini", branch: "main"),
        // The CST text Hudini reads too; the owner's library.
        .package(url: "https://github.com/tonytins/swift-cst.git", from: "0.4.0"),
        .package(url: "https://github.com/tonytins/raylib-swift", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0"),
        // The owner's build-tool plugin: the version from GitVersion.txt and the commits since.
        .package(url: "https://github.com/tonytins/GitVersion", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.0"),
        // Headless and verbose runs log through it; it's already in the graph through swift-configuration.
        .package(url: "https://github.com/apple/swift-log", from: "1.16.0"),
    ],
    targets: [
        // The game: its session and scene (tested without a window), and its drawing and windows.
        .executableTarget(name: "simburbia", dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "Configuration", package: "swift-configuration"),
            .product(name: "Hudini", package: "hudini"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "Raylib", package: "raylib-swift"),
            .product(name: "SimAntics", package: "SimAntics"),
            .product(name: "SwiftCST", package: "swift-cst"),
            .product(name: "TSOConfig", package: "TSOContent"),
            .product(name: "TSOContent", package: "TSOContent"),
            .product(name: "TSOFiles", package: "TSOFiles"),
            .product(name: "GitVersion", package: "GitVersion"),
        ], path: "Client/Sources", plugins: [.plugin(name: "GitVersionPlugin", package: "GitVersion")]),
        .testTarget(name: "SimburbiaTests", dependencies: [
            "simburbia",
            .product(name: "SimAntics", package: "SimAntics"),
            .product(name: "TSOContent", package: "TSOContent"),
            .product(name: "TSOFiles", package: "TSOFiles"),
            // The interface documents are read with Hudini, as the client reads them.
            .product(name: "Hudini", package: "hudini"),
        ], path: "Client/Tests"),
    ],
    swiftLanguageModes: [.v6]
)
