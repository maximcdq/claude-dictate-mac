import AppKit
import DictateAnimations
import DictateCore

final class Dictation {
    // idle → arming (hotkey down, not yet held long enough) → holding (recording) → finishing (waiting for the final text)
    enum Phase { case idle, arming, holding, finishing }

    let settings: SettingsStore
    let pty = ClaudePty()
    let indicator: BadgeIndicator
    let caret: CaretIndicator
    let notch: NotchIndicator
    var style = IndicatorStyle.badge  // picked as a dictation begins
    var held = false  // the hotkey is down
    var beganAt = Date()
    var restartPending = false  // the hidden session restarts for new settings once this dictation is over
    var phase = Phase.idle
    var isActive: Bool { phase == .holding || phase == .finishing }
    var blocksKeys: Bool { isActive && !cancelled }  // a cancelled dictation types nothing more: keys go through
    var cancelled = false
    var detached = false  // no field, or focus left it: nothing is typed, the final text goes to the clipboard
    var searchUntil: Date?  // no field at the start: Chrome may still be building its tree, so look a little longer
    var releasedAt = Date()
    var spaceTimer: Timer?
    var pollTimer: Timer?
    var typed: [Character] = []  // what this dictation has put in the field so far
    var target: AXUIElement?

    // the hotkey only counts when held: a tap, or the key with another (Fn+F5, ⌘C), passes through untouched
    let holdToStart: TimeInterval = 0.3
    let releaseTail: TimeInterval = 0.5  // people let go of the hotkey while still saying the last word
    var pending: DispatchWorkItem?

    // Claude Code /voice ends a recording after 2 minutes or 15 s of silence (code.claude.com/docs/en/voice-dictation).
    // While the hotkey is still held that is only a pause: once that recording's final text is in, the next one starts and
    // appends to the same prompt, so a dictation runs as long as the hotkey is held.
    static let maxRecording: TimeInterval = 125  // in case Claude's own stop goes unnoticed
    var recordingStart = Date()
    var continuing = false  // between Claude's stop and the next recording
    var pausedAt = Date()

    init(settings: SettingsStore) {
        self.settings = settings
        // the meter records from the mic the dictation uses: the built-in one, or the default input
        let input = { settings[.builtInMic] ? Mic.builtIn : nil }
        indicator = BadgeIndicator(meter: LevelMeter(input: input))
        caret = CaretIndicator(meter: LevelMeter(input: input), caretRect: caretRect)
        notch = NotchIndicator(meter: LevelMeter(input: input)) { settings.notchLook }
        pty.language = { settings[.language] }
        settings.observe(.language) { [weak self] _ in self?.restartClaude() }
    }

    func start() {
        try? FileManager.default.createDirectory(atPath: Paths.state, withIntermediateDirectories: true)
        installMod()
        pty.start()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }

    var isIdle: Bool { phase == .idle }

    // now, or once the dictation in progress is over
    func restartClaude() {
        guard phase == .idle else { restartPending = true; return }
        restartPending = false
        pty.restart()
    }

    func hotkeyDown() {
        held = true
        // the hotkey back down within the release tail: the same dictation goes on
        if phase == .holding { cancelPending(); return }
        if phase == .arming { return }
        guard pty.isReady else { log("hotkey ignored: claude is still starting"); return }
        guard phase == .idle else { log("hotkey ignored: the previous dictation is still finishing"); return }
        phase = .arming
        schedule(after: holdToStart) { [weak self] in self?.begin() }
    }

    // another key while the hotkey is down before recording began: it is a modifier here (Fn+F5, ⌘C and the like)
    func keyWhileArming() {
        guard phase == .arming else { return }
        cancelPending()
        phase = .idle
    }

    private func begin() {
        guard phase == .arming else { return }
        enableAppAccessibility()  // Chrome and Electron only report their fields once asked
        let field = focusedElement()
        let focus = focusState(field)
        let takesText = focus != .noField
        if takesText { log("typing into \(focus == .unknown ? "an unreported field" : role(of: field)) in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")") }
        phase = .holding
        cancelled = false
        // without a field the recording starts all the same, so no word is lost: the text waits for a field that
        // shows up within half a second, or else goes to the clipboard
        detached = !takesText
        searchUntil = takesText ? nil : Date().addingTimeInterval(0.5)
        continuing = false
        typed = []
        target = focus == .field ? field : nil
        beganAt = Date()
        if settings[.builtInMic] { Mic.useBuiltIn() }
        if settings[.pauseMedia] { NowPlaying.pauseIfPlaying() }
        style = settings[.indicator]
        if style == .notch, !notch.show() { style = .badge }  // no notch on the pointer's screen
        switch style {
        case .badge:
            indicator.show()
            indicator.badge.listen()
        case .caret:
            caret.show()
            caret.bar.listen()
        case .notch:
            break  // shown above
        }
        startSpaces()
    }

    // a held key repeats ~30 times a second; /voice treats a steady stream of spaces as "Space held"
    private func startSpaces() {
        recordingStart = Date()
        spaceTimer?.invalidate()
        spaceTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in self?.pty.write(" ") }
    }

    private func stopSpaces() {
        spaceTimer?.invalidate()
        spaceTimer = nil
    }

    func hotkeyUp() {
        held = false
        switch phase {
        case .arming:  // a tap: nothing happened, nothing to undo
            cancelPending()
            phase = .idle
        case .holding:
            schedule(after: releaseTail) { [weak self] in self?.release() }
        default: break
        }
    }

    // Esc: drop this dictation and take back what it typed
    func escape() {
        guard isActive else { return }
        if !detached, !typed.isEmpty { Keyboard.backspace(typed.count) }
        typed = []
        cancelled = true
        cancelPending()
        release()
    }

    // A shortcut with a modifier hotkey held a little long (⌘ held, then Tab): the key goes to the app and the
    // dictation is dropped, if it has not typed anything yet. Returns whether it was dropped.
    func abortForShortcut() -> Bool {
        guard phase == .holding, typed.isEmpty, Date().timeIntervalSince(beganAt) < 1.5 else { return false }
        log("a shortcut with the hotkey: dictation dropped")
        escape()
        return true
    }

    private func schedule(after delay: TimeInterval, _ fn: @escaping () -> Void) {
        cancelPending()
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            fn()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    private func release() {
        guard phase == .holding else { return }
        continuing = false
        searchUntil = nil
        stopSpaces()
        switch style {
        case .badge: indicator.badge.process()
        case .caret: caret.bar.process()
        case .notch: notch.process()
        }
        phase = .finishing
        releasedAt = Date()
    }

    private func live() -> String {
        ((try? String(contentsOfFile: Paths.live, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Brings the field from `typed` to `text`: erase back to the common prefix, type the rest.
    private func sync(_ text: String) {
        guard !cancelled, !detached else { return }
        if let target, let now = focusedElement(), !CFEqual(target, now) {
            detached = true
            log("focus moved: typing stopped")
            return
        }
        let goal = Array(text)
        var common = 0
        while common < typed.count, common < goal.count, typed[common] == goal[common] { common += 1 }
        guard common < typed.count || common < goal.count else { return }
        Keyboard.backspace(typed.count - common)
        Keyboard.type(String(goal[common...]))
        typed = goal
    }

    // Whether the recording that stopped at `since` has its final text in.
    private func finalIn(since: Date) -> Bool {
        let elapsed = Date().timeIntervalSince(since)
        let noSpeech = pty.lastNoSpeechAt > since
        // final text is in once /voice stops drawing "processing…"
        let processed = pty.lastProcessingAt > since && Date().timeIntervalSince(pty.lastProcessingAt) > 0.3
        let tooShort = elapsed > 0.6 && pty.lastProcessingAt < since  // stopped before recording began
        return noSpeech || processed || tooShort || elapsed > 10
    }

    private func tick() {
        if style == .caret, phase == .holding || phase == .finishing { caret.follow() }  // it moves as text is typed
        switch phase {
        case .idle, .arming: return
        case .holding:
            if let searchUntil {
                let field = focusedElement()
                if focusedTakesText(field) {
                    self.searchUntil = nil
                    target = field
                    detached = false
                    log("typing into \(role(of: field)) in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
                } else if Date() > searchUntil {
                    self.searchUntil = nil
                    log("no text field in focus (\(role(of: field)) in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")): the text goes to the clipboard")
                }
            }
            sync(live())
            if continuing {
                guard finalIn(since: pausedAt) else { return }
                continuing = false
                startSpaces()
                log("recording continued")
                return
            }
            let stoppedByClaude = pty.lastProcessingAt > recordingStart || pty.lastNoSpeechAt > recordingStart
            guard stoppedByClaude || Date().timeIntervalSince(recordingStart) > Self.maxRecording else { return }
            log(stoppedByClaude ? "claude ended the recording (2 min or 15 s of silence)" : "2 min reached")
            if held, pending == nil {
                stopSpaces()  // a released Space, so /voice can start over when the spaces resume
                continuing = true
                pausedAt = Date()
            } else {
                cancelPending()
                release()
            }
        case .finishing:
            let t = live()
            sync(t)
            guard finalIn(since: releasedAt) else { return }
            finish(text: t)
        }
    }

    private func finish(text: String) {
        try? "clear".write(toFile: Paths.control, atomically: true, encoding: .utf8)
        phase = .idle
        Mic.restore()
        NowPlaying.resume()
        if restartPending { restartClaude() }
        log("done: \(text.count) chars\(cancelled ? ", cancelled" : "")\(detached ? (target == nil ? ", to the clipboard" : ", focus moved, to the clipboard") : "")")
        // the clipboard only when the text did not land in a field: typed text leaves it alone
        if !cancelled, !text.isEmpty, detached {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        if style == .caret { return caret.hide() }
        if style == .notch { return cancelled ? notch.hide() : notch.done(empty: text.isEmpty) }
        if cancelled { return indicator.hide() }
        if text.isEmpty {
            indicator.badge.empty()
            return indicator.hide(after: 0.7)
        }
        indicator.badge.done(detached ? .copied : .typed)
        indicator.hide(after: detached ? 0.9 : 0.8)
    }
}
