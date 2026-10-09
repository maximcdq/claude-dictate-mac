import DictateAnimations
import DictateCore

// Every setting of the app, in one place. To add one: declare it here, show it in a pane (Settings/Panes), and
// observe it where the app reacts to it (`settings.observe(.name) { … }`), or just read `settings[.name]` when needed.
extension Setting {
    static var hotkey: Setting<Hotkey> { .init("hotkey", default: .fn) }
    // stored as "indicatorStyle" since the notch became the default in 0.4: the old "indicator" key is left behind,
    // so every install moves to the notch once and can pick the badge or the caret again
    static var indicator: Setting<IndicatorStyle> { .init("indicatorStyle", default: .notch) }
    // the notch drips: on or just the glow; length and width (1 small, up to 2), how many, how much they melt
    // together 0...1, the glow 0...1 (0 none)
    static var drips: Setting<Bool> { .init("drips", default: false) }
    static var dripLength: Setting<Double> { .init("dripLength", default: 1) }
    static var dripWidth: Setting<Double> { .init("dripWidth", default: 1) }
    static var dripCount: Setting<Double> { .init("dripCount", default: 5) }
    static var dripBlend: Setting<Double> { .init("dripBlend", default: 0.5) }
    static var dripGlow: Setting<Double> { .init("dripGlow", default: 0.5) }
    // the result icon by the notch: on Liquid Glass or bare, on the notch's right or left or below it
    static var resultGlass: Setting<Bool> { .init("resultGlass", default: true) }
    static var resultPlace: Setting<NotchResultPlace> { .init("resultSide", default: .below) }
    // a BCP 47 code passed to the hidden session as Claude Code's `language`; empty follows the user's own setting
    static var language: Setting<String> { .init("language", default: "") }
    // record with the Mac's own mic while dictating, so AirPods stay in their high-quality mode
    static var builtInMic: Setting<Bool> { .init("builtInMic", default: true) }
    // pause music and videos while dictating, play them on afterwards
    static var pauseMedia: Setting<Bool> { .init("pauseMedia", default: true) }
    static var autoUpdate: Setting<Bool> { .init("autoUpdate", default: true) }
    // stay in the Dock with Settings closed; off, the app shows in the Dock only while Settings is open
    static var keepInDock: Setting<Bool> { .init("keepInDock", default: false) }
}

extension SettingsStore {
    var notchLook: NotchLook {
        NotchLook(drips: self[.drips], length: self[.dripLength], width: self[.dripWidth],
                  count: Int(self[.dripCount].rounded()), blend: self[.dripBlend], glow: self[.dripGlow],
                  glass: self[.resultGlass], result: self[.resultPlace])
    }
}

// Claude Code /voice's dictation languages (code.claude.com/docs/en/voice-dictation#change-the-dictation-language)
let dictationLanguages: [(code: String, name: String)] = [
    ("cs", "Czech"), ("da", "Danish"), ("nl", "Dutch"), ("en", "English"), ("fr", "French"), ("de", "German"),
    ("el", "Greek"), ("hi", "Hindi"), ("id", "Indonesian"), ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"),
    ("no", "Norwegian"), ("pl", "Polish"), ("pt", "Portuguese"), ("ru", "Russian"), ("es", "Spanish"),
    ("sv", "Swedish"), ("tr", "Turkish"), ("uk", "Ukrainian"),
]
