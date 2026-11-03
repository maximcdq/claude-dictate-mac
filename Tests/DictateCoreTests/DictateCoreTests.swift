import CoreGraphics
import Foundation
import Testing
@testable import DictateCore

@Test func versionsCompareByNumber() {
    #expect(Version("0.1.10")! > Version("0.1.9")!)
    #expect(Version("v0.2.0")! > Version("0.1.3")!)
    #expect(Version("1.0")! == Version("1.0.0")!)
    #expect(Version("0.2.0-beta") == nil)
}

@Test func hotkeyTellsSidesApart() {
    let rightCommandDown = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
    #expect(Hotkey.rightCommand.isDown(rightCommandDown))
    #expect(!Hotkey.leftCommand.isDown(rightCommandDown))
    #expect(Hotkey.fn.isDown(.maskSecondaryFn))
}

@Test func claudeVersionSkipsUnfinishedAndFailed() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dictate-versions-\(UUID())").path
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    for (i, name) in ["old", "previous", "newest", "writing"].enumerated() {
        let path = "\(dir)/\(name)"
        FileManager.default.createFile(atPath: path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: name == "writing" ? 0o644 : 0o755,
                                               .modificationDate: Date(timeIntervalSince1970: Double(i) * 100)], ofItemAtPath: path)
    }
    #expect(claudeVersion(in: dir) == "\(dir)/newest")
    #expect(claudeVersion(in: dir, avoiding: ["\(dir)/newest"]) == "\(dir)/previous")
    #expect(claudeVersion(in: dir, avoiding: ["\(dir)/newest", "\(dir)/previous", "\(dir)/old"]) == "\(dir)/newest")
    #expect(claudeVersion(in: "\(dir)/none") == nil)
}

private enum Style: String { case a, b }

@Test func settingsStoreReadsDefaultsWritesAndNotifies() {
    let defaults = UserDefaults(suiteName: "dictate-tests-\(UUID())")!
    let store = SettingsStore(defaults: defaults)
    let style = Setting<Style>("style", default: .a)
    let flag = Setting<Bool>("flag", default: true)
    let size = Setting<Double>("size", default: 1)
    #expect(store[style] == .a)
    #expect(store[flag])
    #expect(store[size] == 1)
    store[size] = 1.5
    #expect(store[size] == 1.5)
    var seen: Style?
    store.observe(style) { seen = $0 }
    store[style] = .b
    #expect(store[style] == .b)
    #expect(seen == .b)
    defaults.set("garbage", forKey: "style")
    #expect(store[style] == .a)
}
