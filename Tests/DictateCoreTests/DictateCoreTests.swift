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

private enum Style: String { case a, b }

@Test func settingsStoreReadsDefaultsWritesAndNotifies() {
    let defaults = UserDefaults(suiteName: "dictate-tests-\(UUID())")!
    let store = SettingsStore(defaults: defaults)
    let style = Setting<Style>("style", default: .a)
    let flag = Setting<Bool>("flag", default: true)
    #expect(store[style] == .a)
    #expect(store[flag])
    var seen: Style?
    store.observe(style) { seen = $0 }
    store[style] = .b
    #expect(store[style] == .b)
    #expect(seen == .b)
    defaults.set("garbage", forKey: "style")
    #expect(store[style] == .a)
}
