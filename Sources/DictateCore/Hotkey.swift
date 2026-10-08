import CoreGraphics

// The key held to dictate: Fn or one side of a modifier. Each is told apart in a flagsChanged event by its key code,
// and whether it is down by its bit in the event's flags (the device-dependent bits name the side).
public enum Hotkey: String, CaseIterable, Identifiable {
    case fn, rightCommand, leftCommand, rightOption, leftOption, rightControl, leftControl

    public var id: String { rawValue }

    public var keyCode: Int64 {
        switch self {
        case .fn: 63  // kVK_Function
        case .rightCommand: 54
        case .leftCommand: 55
        case .rightOption: 61
        case .leftOption: 58
        case .rightControl: 62
        case .leftControl: 59
        }
    }

    // NX_DEVICE*KEYMASK from IOKit's IOLLEvent.h; Fn has no sides
    private var mask: UInt64 {
        switch self {
        case .fn: CGEventFlags.maskSecondaryFn.rawValue
        case .rightCommand: 0x10
        case .leftCommand: 0x08
        case .rightOption: 0x40
        case .leftOption: 0x20
        case .rightControl: 0x2000
        case .leftControl: 0x01
        }
    }

    public func isDown(_ flags: CGEventFlags) -> Bool { flags.rawValue & mask != 0 }

    // the key codes of every key that can be a hotkey: another of them changing while this one arms is a combination
    public static let modifierKeyCodes: Set<Int64> = Set(allCases.map(\.keyCode)).union([56, 60, 57])  // + Shift L/R, Caps Lock

    public var title: String {
        switch self {
        case .fn: "Fn (🌐)"
        case .rightCommand: "Right ⌘ Command"
        case .leftCommand: "Left ⌘ Command"
        case .rightOption: "Right ⌥ Option"
        case .leftOption: "Left ⌥ Option"
        case .rightControl: "Right ⌃ Control"
        case .leftControl: "Left ⌃ Control"
        }
    }

    public var shortTitle: String {
        switch self {
        case .fn: "Fn"
        case .rightCommand: "right ⌘"
        case .leftCommand: "left ⌘"
        case .rightOption: "right ⌥"
        case .leftOption: "left ⌥"
        case .rightControl: "right ⌃"
        case .leftControl: "left ⌃"
        }
    }
}
