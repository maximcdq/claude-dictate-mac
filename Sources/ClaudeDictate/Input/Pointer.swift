import AppKit
import DictateCore

// While dictating the pointer stays put and hidden: a finger resting on the trackpad (the dictation started by a
// Force Click holds the button down) would otherwise move it, select text and click.
enum Pointer {
    private static var frozenAt: CGPoint?

    static func hold(_ on: Bool) {
        if on, frozenAt == nil {
            frozenAt = CGEvent(source: nil)?.location
            CGAssociateMouseAndMouseCursorPosition(0)
            if canHideInBackground { CGDisplayHideCursor(CGMainDisplayID()) }
            log("pointer frozen\(canHideInBackground ? " and hidden" : "")")
        } else if !on, frozenAt != nil {
            frozenAt = nil
            CGAssociateMouseAndMouseCursorPosition(1)
            if canHideInBackground { CGDisplayShowCursor(CGMainDisplayID()) }
        }
    }

    // puts it back if a movement got through anyway
    static func pin() {
        if let frozenAt { CGWarpMouseCursorPosition(frozenAt) }
    }

    // a background app may hide the cursor only after asking the window server (private, looked up at runtime)
    private static let canHideInBackground: Bool = {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let lib = dlopen(nil, RTLD_NOW),
              let connection = dlsym(lib, "_CGSDefaultConnection"),
              let setProperty = dlsym(lib, "CGSSetConnectionProperty") else { return false }
        let cid = unsafeBitCast(connection, to: DefaultConnection.self)()
        return unsafeBitCast(setProperty, to: SetProperty.self)(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }()
}
