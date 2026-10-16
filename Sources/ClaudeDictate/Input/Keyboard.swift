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
        // chunks of up to 16 UTF-16 units that end on a character boundary: a split emoji or composed letter comes out as garbage
        var chunk: [UniChar] = []
        for character in s {
            let units = Array(String(character).utf16)
            if !chunk.isEmpty, chunk.count + units.count > 16 { post(0, text: chunk); chunk = [] }
            chunk += units
        }
        if !chunk.isEmpty { post(0, text: chunk) }
    }

    static func backspace(_ n: Int) { (0..<n).forEach { _ in post(51) } }  // kVK_Delete
}
