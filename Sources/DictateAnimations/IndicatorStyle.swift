// Which indicator a dictation shows.
public enum IndicatorStyle: String, CaseIterable, Identifiable {
    case badge, caret, notch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .badge: "Badge at the pointer"
        case .caret: "Bar at the caret (Claude Code style)"
        case .notch: "The notch"
        }
    }

    public var detail: String {
        switch self {
        case .badge: "A Liquid Glass capsule next to the mouse pointer that reacts to your voice and ends with a check, a copy icon or a soft coral spin."
        case .caret: "Claude Code's own /voice level bar, drawn just right of the text caret."
        case .notch: "The MacBook's notch glows with your voice, small black drips can seep from it, and a check or a clipboard comes out beside it. On a screen without a notch, the badge shows instead."
        }
    }
}
