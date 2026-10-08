// swift-tools-version:6.0
import PackageDescription

// ClaudeDictate is split by concern:
// - DictateCore: paths, log, versions, the hotkey model and the settings store (no UI)
// - DictateAnimations: the dictation indicators (badge at the pointer, bar at the caret), pure drawing
// - DictateUpdater: self-update from GitHub releases
// - ClaudeDictate: the app itself, wiring the above to Claude Code, the mic, the keyboard and the menu bar
let package = Package(
    name: "ClaudeDictate",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "DictateCore"),
        .target(name: "DictateAnimations"),
        .target(name: "DictateUpdater", dependencies: ["DictateCore"]),
        .executableTarget(name: "ClaudeDictate", dependencies: ["DictateCore", "DictateAnimations", "DictateUpdater"]),
        .testTarget(name: "DictateCoreTests", dependencies: ["DictateCore"]),
    ],
    swiftLanguageModes: [.v5]
)
