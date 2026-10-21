// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Speek2Me",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Speek2Me", targets: ["Speek2Me"]),
        .executable(name: "speek2me-hook", targets: ["Speek2MeHook"]),
    ],
    targets: [
        // Everything without a window: events, hook parsing, inbox, condensing, speaking, config patching.
        .target(name: "Speek2MeCore"),
        // The command the Claude Code and Codex hooks run. It only drops a file into the inbox.
        .executableTarget(name: "Speek2MeHook", dependencies: ["Speek2MeCore"]),
        // The menu-bar app. AppKit callbacks are simpler in the Swift 5 language mode.
        .executableTarget(
            name: "Speek2Me",
            dependencies: ["Speek2MeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "Speek2MeCoreTests", dependencies: ["Speek2MeCore"]),
    ]
)
