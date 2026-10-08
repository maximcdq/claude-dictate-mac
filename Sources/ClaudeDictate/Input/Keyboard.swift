import CoreGraphics

// MARK: - Typing into the focused field

let syntheticMark: Int64 = 0x0D1C7A7E  // eventSourceUserData of our own key events, so the hotkey tap skips them

enum Keyboard {
    // a private source: the physically held hotkey must not leak into these events (Fn+Delete is forward delete, ⌘A selects all)
    static let source = CGEventSource(stateID: .privateState)

    static func post(_ key: CGKeyCode, text: [UniChar]? = nil) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.flags = []
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMark)
            if let text { e.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text) }
            e.post(tap: .cghidEventTap)
        }
    }

    static func type(_ s: String) {
        let units = Array(s.utf16)
        stride(from: 0, to: units.count, by: 16).forEach { post(0, text: Array(units[$0..<min($0 + 16, units.count)])) }
    }

    static func backspace(_ n: Int) { (0..<n).forEach { _ in post(51) } }  // kVK_Delete
}
