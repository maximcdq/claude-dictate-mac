import DictateAnimations
import DictateCore

// Every setting of the app, in one place. To add one: declare it here, show it in a pane (Settings/Panes), and
// observe it where the app reacts to it (`settings.observe(.name) { … }`), or just read `settings[.name]` when needed.
extension Setting {
    static var hotkey: Setting<Hotkey> { .init("hotkey", default: .fn) }
    static var indicator: Setting<IndicatorStyle> { .init("indicator", default: .badge) }
    // a BCP 47 code passed to the hidden session as Claude Code's `language`; empty follows the user's own setting
    static var language: Setting<String> { .init("language", default: "") }
    // record with the Mac's own mic while dictating, so AirPods stay in their high-quality mode
    static var builtInMic: Setting<Bool> { .init("builtInMic", default: true) }
    static var autoUpdate: Setting<Bool> { .init("autoUpdate", default: true) }
}

// Claude Code /voice's dictation languages (code.claude.com/docs/en/voice-dictation#change-the-dictation-language)
let dictationLanguages: [(code: String, name: String)] = [
    ("cs", "Czech"), ("da", "Danish"), ("nl", "Dutch"), ("en", "English"), ("fr", "French"), ("de", "German"),
    ("el", "Greek"), ("hi", "Hindi"), ("id", "Indonesian"), ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"),
    ("no", "Norwegian"), ("pl", "Polish"), ("pt", "Portuguese"), ("ru", "Russian"), ("es", "Spanish"),
    ("sv", "Swedish"), ("tr", "Turkish"), ("uk", "Ukrainian"),
]
