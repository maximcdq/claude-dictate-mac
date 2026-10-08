import AppKit
import DictateCore

// The event tap: the hotkey's presses drive the dictation; while it records, keys are dropped and Esc cancels.
// Runs on the main run loop, so it reads and drives `dictation` directly.
final class HotkeyTap {
    private let dictation: Dictation
    private let settings: SettingsStore
    private var tap: CFMachPort?
    private var isDown = false

    init(dictation: Dictation, settings: SettingsStore) {
        self.dictation = dictation
        self.settings = settings
        // a key switched mid-press would never see its release
        settings.observe(.hotkey) { [weak self] _ in self?.release() }
    }

    private var hotkey: Hotkey { settings[.hotkey] }

    func install() {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        // an active (.defaultTap) tap needs only Accessibility; a listen-only one would need Input Monitoring too
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
                                            Unmanaged<HotkeyTap>.fromOpaque(info!).takeUnretainedValue().handle(type, event)
                                        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.install() }  // no permission yet
            return
        }
        tap = t
        log("Accessibility trusted: \(AXIsProcessTrusted())")
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        log("hotkey tap installed (\(hotkey.shortTitle))")
    }

    private func release() {
        guard isDown else { return }
        isDown = false
        dictation.hotkeyUp()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMark { return Unmanaged.passUnretained(event) }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log("event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // a release that came while the tap was off is lost: take the key's state from the system
            if isDown, !hotkey.isDown(CGEventSource.flagsState(.combinedSessionState)) { release() }
        case .flagsChanged where key == hotkey.keyCode:
            // a down always counts, even after a lost release: comparing with the stored state would drop it
            if hotkey.isDown(event.flags) {
                isDown = true
                dictation.hotkeyDown()
            } else {
                release()
            }
        case .flagsChanged where Hotkey.modifierKeyCodes.contains(key):
            dictation.keyWhileArming()  // another modifier with the hotkey (⌘⇧…): a shortcut, not a dictation
        case .keyDown, .keyUp:
            if type == .keyDown, dictation.phase == .arming { dictation.keyWhileArming() }  // Fn+F5: let it through
            // a modifier hotkey held a little long before its shortcut's key: the shortcut wins
            if type == .keyDown, hotkey != .fn, key != 53, dictation.abortForShortcut() { break }
            // while dictating only the voice writes: keys are dropped (an early Enter would send the interim text and
            // the final fix-up would land in the emptied box); Esc cancels the dictation
            guard dictation.blocksKeys else { break }
            if key == 53, type == .keyDown { dictation.escape() }  // kVK_Escape
            return nil
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
}
