// ClaudeDictate: hold Fn anywhere -> Claude Code /voice transcribes -> text is typed live into the focused field.
// Runs `claude --plugin-dir <state>/mod` in a hidden pty with DICTATE_STATE_DIR set; holding Fn streams spaces
// into it (what a held Space key looks like to a terminal app), the mod mirrors the prompt draft to
// <state>/live.txt, and this app types it into the focused field as it comes, fixing it up to the final text.
import AppKit
import AVFoundation
import CoreAudio
import Darwin

let home = FileManager.default.homeDirectoryForCurrentUser.path
let stateDir = "\(home)/Library/Application Support/ClaudeDictate"  // install.sh puts the mod here too
let liveFile = "\(stateDir)/live.txt"
let controlFile = "\(stateDir)/control.txt"
let agentDir = "\(stateDir)/agent"
let modDir = "\(stateDir)/mod"

// the newest real binary of the native install: ~/.local/bin/claude is a wrapper script that puts claude in a pty
// of its own, which would leave it orphaned (and out of our process group) when the app quits; other installs
// (Homebrew, npm) are found on the usual paths
func claudeBinary() -> String {
    let dir = "\(home)/.local/share/claude/versions"
    let fm = FileManager.default
    let newest = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).max { a, b in
        let da = (try? fm.attributesOfItem(atPath: "\(dir)/\(a)")[.modificationDate] as? Date) ?? .distantPast
        let db = (try? fm.attributesOfItem(atPath: "\(dir)/\(b)")[.modificationDate] as? Date) ?? .distantPast
        return da < db
    }
    if let newest { return "\(dir)/\(newest)" }
    let found = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin"]
        .map { "\($0)/claude" }.first { fm.isExecutableFile(atPath: $0) }
    return found.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } ?? "\(home)/.local/bin/claude"
}

let logFile = "\(home)/Library/Logs/ClaudeDictate.log"
func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    if let h = FileHandle(forWritingAtPath: logFile) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(toFile: logFile, atomically: true, encoding: .utf8) }
}

// MARK: - Claude Code in a hidden pty

final class ClaudePty {
    private(set) var master: Int32 = -1
    private var pid: pid_t = 0
    private var reader: DispatchSourceRead?
    private var exitWatch: DispatchSourceProcess?
    private var startedAt = Date()
    private var trustAnswered = false
    private var tail = ""
    private(set) var lastProcessingAt = Date.distantPast
    private(set) var lastNoSpeechAt = Date.distantPast
    var isReady: Bool { Date().timeIntervalSince(startedAt) > 8 }

    // a hard crash of the app leaves its claude running; the next start finishes it off
    private let pidFile = "\(stateDir)/claude.pid"

    private func killLeftover() {
        guard let old = (try? String(contentsOfFile: pidFile, encoding: .utf8)).flatMap({ pid_t($0) }), old > 0 else { return }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(old, &path, UInt32(path.count)) > 0, String(cString: path).contains("/claude/versions/") {
            kill(-old, SIGKILL)
            log("killed leftover claude \(old)")
        }
    }

    func start() {
        killLeftover()
        var m: Int32 = 0, s: Int32 = 0
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&m, &s, nil, nil, &size) == 0 else { log("openpty failed"); return }
        let slavePath = String(cString: ptsname(m))
        close(s)
        master = m

        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        for fd: Int32 in 0...2 { posix_spawn_file_actions_addopen(&fa, fd, slavePath, O_RDWR, 0) }
        posix_spawn_file_actions_addchdir(&fa, agentDir)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        // drop markers of whatever claude session launched this app, or the child thinks it is a subsession
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CLAUDE_CODE") && $0.key != "CLAUDECODE" }
        env["DICTATE_STATE_DIR"] = stateDir
        env["TERM"] = "xterm-256color"
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let bin = claudeBinary()
        // voice is off in the user's settings (Space types spaces in their sessions); this session turns it on
        let args: [String] = [bin, "--plugin-dir", modDir, "--settings", #"{"voiceEnabled":true,"voice":{"enabled":true,"mode":"hold"}}"#]
        let argv = args.map { strdup($0) } + [nil]
        defer { (envp + argv).forEach { free($0) } }

        try? FileManager.default.createDirectory(atPath: agentDir, withIntermediateDirectories: true)
        let rc = posix_spawn(&pid, bin, &fa, &attr, argv, envp)
        posix_spawn_file_actions_destroy(&fa)
        posix_spawnattr_destroy(&attr)
        guard rc == 0 else { log("spawn failed: \(rc)"); return }
        startedAt = Date()
        trustAnswered = false
        try? "\(pid)".write(toFile: pidFile, atomically: true, encoding: .utf8)
        log("claude started, pid \(pid)")

        let r = DispatchSource.makeReadSource(fileDescriptor: m, queue: .main)
        r.setEventHandler { [weak self] in self?.drain() }
        r.resume()
        reader = r

        let w = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        w.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(self.pid, &status, 0)
            let plain = self.tail.replacingOccurrences(of: "\u{1b}\\[[0-9;?<>=]*[A-Za-z~]", with: " ", options: .regularExpression)
            log("claude exited (\(status)), restarting; last output: \(plain.suffix(800))")
            self.reader?.cancel()
            self.exitWatch?.cancel()
            close(self.master)
            self.master = -1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.start() }
        }
        w.resume()
        exitWatch = w
    }

    // The screen output must be drained or claude blocks; it is also where /voice reports its state.
    private func drain() {
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = read(master, &buf, buf.count)
        guard n > 0 else { return }
        let text = String(decoding: buf[0..<n], as: UTF8.self)
        tail = String((tail + text).suffix(3000))
        if text.contains("processing") { lastProcessingAt = Date() }
        if text.contains("No speech detected") { lastNoSpeechAt = Date() }
        // first run in agentDir (an empty folder of ours): the trust prompt defaults to "No, exit"; pick "Yes"
        if !trustAnswered,
           tail.replacingOccurrences(of: "(\u{1b}\\[[0-9;?<>=]*[A-Za-z~]|\\s)+", with: " ", options: .regularExpression)
               .contains("I trust this folder") {
            trustAnswered = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.write("\u{1b}[B") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.write("\r") }
        }
    }

    // claude runs in its own session (setsid), so its pid is the process group id
    func stop() {
        exitWatch?.cancel()
        if pid > 0 { kill(-pid, SIGKILL) }  // claude ignores SIGTERM; this session holds nothing worth saving
    }

    func write(_ s: String) {
        guard master >= 0 else { return }
        _ = s.withCString { Darwin.write(master, $0, strlen($0)) }
    }
}

// MARK: - Built-in mic for dictation
// Claude records from the system default input, which macOS moves to AirPods whenever they connect. For the
// length of a dictation the default input is the Mac's own mic (AirPods stay in their high-quality mode),
// then it goes back to whatever it was.

enum Mic {
    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static var defaultInput: AudioDeviceID {
        get {
            var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var a = address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
            return id
        }
        set {
            var id = newValue
            var a = address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        }
    }

    static var builtIn: AudioDeviceID? {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
        return ids.first { id in
            var transport: UInt32 = 0, tsize = UInt32(MemoryLayout<UInt32>.size)
            var t = address(kAudioDevicePropertyTransportType)
            AudioObjectGetPropertyData(id, &t, 0, nil, &tsize, &transport)
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var ssize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &ssize)
            return transport == kAudioDeviceTransportTypeBuiltIn && ssize > 0
        }
    }

    // The input to go back to, kept on disk by UID (device ids change across reboots and reconnects): if the app
    // dies mid-dictation, the next start puts it back.
    private static let previousFile = "\(stateDir)/previous-input.txt"

    private static func uid(_ id: AudioDeviceID) -> String? {
        var a = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func device(uid: String) -> AudioDeviceID? {
        var a = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        return status == noErr && id != 0 ? id : nil
    }

    static func useBuiltIn() {
        guard let mac = builtIn else { log("mic: no built-in input found"); return }
        let current = defaultInput
        guard current != mac, let currentUID = uid(current) else { return }
        try? currentUID.write(toFile: previousFile, atomically: true, encoding: .utf8)
        defaultInput = mac
        log("mic: built-in (\(defaultInput == mac ? "switched" : "switch failed"), was \(currentUID))")
    }

    // also called at launch, to undo a switch a crashed run left behind
    static func restore() {
        guard let prevUID = try? String(contentsOfFile: previousFile, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(atPath: previousFile)
        // unless the user picked another input meanwhile, or that device is gone (AirPods put away)
        guard let mac = builtIn, defaultInput == mac, let prev = device(uid: prevUID) else { return }
        defaultInput = prev
        log("mic: restored \(prevUID)")
    }
}

// MARK: - Recording badge: a Liquid Glass bubble at the mouse pointer
// Carets are reported differently by every app (or not at all: Chrome's address bar), the pointer is always known.
// So the badge rides above-right of the pointer: a glass capsule with a mic that takes Claude Code's /voice colors.
// Claude Code 2.1.292's level and colors: level = sqrt(min(rms16 / 2000, 1)), x1.8 capped at 1; gray under 0.15,
// else hsl(hue 90°/s, s 0.7, l 0.6). Here at 60 fps, smoothed to swell fast and settle softer; black in silence
// instead of gray.

final class VoiceBadge: NSView {
    enum Mode { case off, live, processing }

    // AVAudioEngine can block for seconds while Core Audio reshuffles devices: it lives on a queue of its own, so the
    // main thread, and with it the Fn event tap, never waits on it
    private let micQueue = DispatchQueue(label: "badge.mic")
    private var engine: AVAudioEngine?  // micQueue only
    private var micBusy = false  // main: a start is queued or running
    private var level: CGFloat = 0
    private var smoothed: CGFloat = 0
    private var timer: Timer?
    private var startedAt = Date()  // hue clock, runs on through processing so the color doesn't jump
    private var processingAt = Date()
    private var shownAt = Date()
    private var leavingAt: Date?  // set while the badge fades out: the content eases down with it
    private(set) var mode = Mode.off
    private var device: AudioDeviceID?
    private var lastBufferAt = Date()
    private var restartedAt = Date()

    func listen(device: AudioDeviceID?) {
        guard mode == .off else { return }
        mode = .live
        smoothed = 0
        level = 0
        startedAt = Date()
        shownAt = Date()
        leavingAt = nil
        self.device = device
        startMic()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func step() {
        // The engine stops without a word when its device changes under it (Claude opening the same mic in another
        // format does that), and the badge would sit black while the transcript runs: no buffers for a while, even
        // silent ones, means it went quiet, so it starts over.
        let now = Date()
        if mode == .live, !micBusy, now.timeIntervalSince(lastBufferAt) > 0.4, now.timeIntervalSince(restartedAt) > 1 {
            log("mic: no audio reaching the badge, restarting its engine")
            stopMic()
            startMic()
        }
        needsDisplay = true
    }

    private func startMic() {
        restartedAt = Date()
        lastBufferAt = Date()
        micBusy = true
        let device = self.device
        micQueue.async { [weak self] in
            self?.startEngine(device: device)
            DispatchQueue.main.async { self?.micBusy = false }
        }
    }

    private func stopMic() {
        micQueue.async { [weak self] in
            guard let engine = self?.engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self?.engine = nil
        }
    }

    // micQueue
    private func startEngine(device: AudioDeviceID?) {
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        // bound to the device itself: an engine on the default input stops dead (no buffers) when the default
        // moves to the built-in mic right under it, and the badge would sit gray and still
        if var id = device, let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { log("mic: the input has no format yet"); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms16 = sqrt(sum / Float(max(n, 1))) * 32768  // Claude measures 16-bit samples
            let v = CGFloat(sqrt(min(rms16 / 2000, 1)))
            DispatchQueue.main.async {
                self?.level = v
                self?.lastBufferAt = Date()
            }
        }
        do { try engine.start() } catch { log("mic: \(error)") }
    }

    func process() {
        guard mode == .live else { return }
        mode = .processing
        processingAt = Date()
        stopMic()
    }

    func leave() {
        leavingAt = Date()
    }

    func off() {
        mode = .off
        stopMic()
        timer?.invalidate()
        timer = nil
    }


    private static func hsl(hue: CGFloat) -> NSColor {
        let t = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c: CGFloat = (1 - abs(2 * 0.6 - 1)) * 0.7, x = c * (1 - abs((t / 60).truncatingRemainder(dividingBy: 2) - 1)), m = 0.6 - c / 2
        let (r, g, b): (CGFloat, CGFloat, CGFloat) =
            t < 60 ? (c, x, 0) : t < 120 ? (x, c, 0) : t < 180 ? (0, c, x) : t < 240 ? (0, x, c) : t < 300 ? (x, 0, c) : (c, 0, x)
        return NSColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: 1)
    }

    private func mic(_ color: NSColor, size: CGFloat, center: CGPoint) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let s = image.size
        image.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard mode != .off else { return }
        let now = Date()
        let hue = Self.hsl(hue: CGFloat(now.timeIntervalSince(startedAt)) * 90)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // a horizontal capsule, like the glass it sits in, inset from its edge
        let outline = bounds.insetBy(dx: 3.5, dy: 3.5)
        let capsule = { NSBezierPath(roundedRect: outline, xRadius: outline.height / 2, yRadius: outline.height / 2) }
        // pop in: ease-out with a touch of overshoot over 0.25 s; on the way out, ease down to 85% with the fade
        let t = min(CGFloat(now.timeIntervalSince(shownAt)) / 0.25, 1)
        var pop = 1 + 1.7 * pow(t - 1, 3) + 0.7 * pow(t - 1, 2)
        if let leavingAt {
            let out = min(CGFloat(now.timeIntervalSince(leavingAt)) / Indicator.fadeOut, 1)
            pop *= 1 - 0.15 * out * out
        }

        switch mode {
        case .off: return
        case .live:
            let target = min(level * 1.8, 1)
            smoothed += (target - smoothed) * (target > smoothed ? 0.45 : 0.18)
            let speech = min(max((level - 0.1) / 0.1, 0), 1)  // crossfade around Claude's 0.15 threshold
            // the mic and the ring share one color: black in silence, Claude's hue with the voice
            let color = NSColor.black.blended(withFraction: speech, of: hue)!
            // a soft round glow right around the mic: none in silence, stronger and larger with the voice
            color.withAlphaComponent(0.26 * speech).setFill()
            let glow = outline.height / 2 * (0.5 + 0.42 * smoothed) * pop
            NSBezierPath(ovalIn: NSRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)).fill()
            // a hairline outline in silence that thickens with the level
            let ring = capsule()
            ring.lineWidth = 0.5 + 2.2 * smoothed
            color.withAlphaComponent(0.9).setStroke()
            ring.stroke()
            mic(color, size: 14 * (1 + 0.14 * smoothed) * pop, center: center)
        case .processing:
            // a pulse on the mic, and an arc running round the ring
            let elapsed = CGFloat(now.timeIntervalSince(processingAt))
            let k = (sin(elapsed * .pi * 2 / 2) + 1) / 2
            let gray = 0.3 * k  // pulses up from black, where the live mic rests
            let ring = capsule()
            ring.lineWidth = 0.5
            NSColor(white: 0, alpha: 0.5).setStroke()
            ring.stroke()
            // a colored segment running round the capsule, one lap a second
            let perimeter = 2 * (outline.width - outline.height) + .pi * outline.height
            let run = capsule()
            let dash: [CGFloat] = [perimeter * 0.28, perimeter * 0.72]
            run.setLineDash(dash, count: 2, phase: -elapsed * perimeter)
            run.lineWidth = 2
            run.lineCapStyle = .round
            hue.setStroke()
            run.stroke()
            mic(NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1), size: 14 * pop, center: center)
        }
    }
}

final class Indicator {
    static let fadeIn: TimeInterval = 0.22  // quick in, slower out
    static let fadeOut: TimeInterval = 0.4
    static let size = NSSize(width: 64, height: 36)  // a horizontal capsule
    let badge = VoiceBadge(frame: NSRect(origin: .zero, size: size))
    private let panel: NSPanel
    private var mouseMonitor: Any?
    private var generation = 0  // a show that comes while the previous hide still fades out wins

    init() {
        let frame = NSRect(origin: .zero, size: Self.size)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        let glass = NSGlassEffectView(frame: frame)
        glass.cornerRadius = Self.size.height / 2
        glass.contentView = badge
        panel.contentView = glass
    }

    func show() {
        generation += 1
        stopFollowing()
        badge.off()  // the previous dictation's badge may still be fading out
        follow()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // moved on every pointer event as it arrives (they come faster than the display refreshes), not polled
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in self?.follow() }
    }

    private func stopFollowing() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    // above-right of the pointer's tip, kept on the pointer's screen
    func follow() {
        let m = NSEvent.mouseLocation
        var origin = NSPoint(x: m.x + 12, y: m.y + 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(m) }) {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - Self.size.width)
            origin.y = min(max(origin.y, f.minY), f.maxY - Self.size.height)
        }
        if origin != panel.frame.origin { panel.setFrameOrigin(origin) }
    }

    func hide() {
        let shown = generation
        badge.leave()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == shown else { return }
            self.stopFollowing()
            self.badge.off()
            self.panel.orderOut(nil)
        })
    }
}

// Chrome and Electron build their accessibility tree (and so report the focused field) only when asked.
func enableAppAccessibility() {
    guard let app = NSWorkspace.shared.frontmostApplication else { return }
    AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), "AXManualAccessibility" as CFString, kCFBooleanTrue)
}

// MARK: - Typing into the focused field

let syntheticMark: Int64 = 0x0D1C7A7E  // eventSourceUserData of our own key events, so the Fn tap skips them

enum Keyboard {
    // a private source: the physically held Fn must not leak into these events (Fn+Delete is forward delete)
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

// MARK: - Fn handling

// The field that has keyboard focus, to notice the user clicking elsewhere mid-dictation.
func focusedElement() -> AXUIElement? {
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let el = focused else { return nil }
    return (el as! AXUIElement)
}

// Whether the focused element takes typed text: it has a text caret (a selected text range). The desktop, a file
// list, a button have none, so Fn there does nothing.
func focusedTakesText(_ element: AXUIElement?) -> Bool {
    guard let element else { return false }
    var range: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success && range != nil
}

final class Dictation {
    // idle → arming (Fn down, not yet held long enough) → holding (recording) → finishing (waiting for the final text)
    enum Phase { case idle, arming, holding, finishing }

    let pty = ClaudePty()
    let indicator = Indicator()
    var phase = Phase.idle
    var isActive: Bool { phase == .holding || phase == .finishing }  // keys are blocked only then
    var cancelled = false
    var detached = false  // focus left the field: stop typing, the final text still goes to the clipboard
    var releasedAt = Date()
    var spaceTimer: Timer?
    var pollTimer: Timer?
    var typed: [Character] = []  // what this dictation has put in the field so far
    var target: AXUIElement?

    // Fn only counts when held: a tap, or Fn with another key (Fn+F5), passes through untouched
    let holdToStart: TimeInterval = 0.3
    let releaseTail: TimeInterval = 0.5  // people let go of Fn while still saying the last word
    var pending: DispatchWorkItem?

    // Claude Code /voice ends a recording after 2 minutes or 15 s of silence (code.claude.com/docs/en/voice-dictation).
    // While Fn is still held that is only a pause: once that recording's final text is in, the next one starts and
    // appends to the same prompt, so a dictation runs as long as Fn is held.
    static let maxRecording: TimeInterval = 125  // in case Claude's own stop goes unnoticed
    var recordingStart = Date()
    var continuing = false  // between Claude's stop and the next recording
    var pausedAt = Date()

    func start() {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        pty.start()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }

    func fnDown() {
        // Fn back down within the release tail: the same dictation goes on
        if phase == .holding { cancelPending(); return }
        if phase == .arming { return }
        guard pty.isReady else { log("fn ignored: claude is still starting"); return }
        guard phase == .idle else { log("fn ignored: the previous dictation is still finishing"); return }
        phase = .arming
        schedule(after: holdToStart) { [weak self] in self?.begin() }
    }

    // another key while Fn is down before recording began: Fn is a modifier here (Fn+F5 and the like)
    func keyWhileArming() {
        guard phase == .arming else { return }
        cancelPending()
        phase = .idle
    }

    private func begin() {
        guard phase == .arming else { return }
        enableAppAccessibility()  // Chrome and Electron only report their fields once asked
        let field = focusedElement()
        guard focusedTakesText(field) else { phase = .idle; log("fn ignored: no text field in focus"); return }
        phase = .holding
        cancelled = false
        detached = false
        continuing = false
        typed = []
        target = field
        Mic.useBuiltIn()
        indicator.show()
        indicator.badge.listen(device: Mic.builtIn)
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

    func fnUp() {
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
        stopSpaces()
        indicator.badge.process()
        phase = .finishing
        releasedAt = Date()
    }

    private func live() -> String {
        ((try? String(contentsOfFile: liveFile, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        switch phase {
        case .idle, .arming: return
        case .holding:
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
            if fnIsDown, pending == nil {
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
        try? "clear".write(toFile: controlFile, atomically: true, encoding: .utf8)
        phase = .idle
        indicator.hide()
        Mic.restore()
        log("done: \(text.count) chars\(cancelled ? ", cancelled" : "")\(detached ? ", focus moved" : "")")
        guard !text.isEmpty, !cancelled else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

let dictation = Dictation()
var fnIsDown = false
var tap: CFMachPort?

// Runs on the main run loop, so it reads and drives `dictation` directly.
let callback: CGEventTapCallBack = { _, type, event, _ in
    if event.getIntegerValueField(.eventSourceUserData) == syntheticMark { return Unmanaged.passUnretained(event) }
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        log("event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")), re-enabling")
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        // a Fn release that came while the tap was off is lost: take Fn's state from the system
        if fnIsDown, !CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn) {
            fnIsDown = false
            dictation.fnUp()
        }
    case .flagsChanged where key == 63:  // kVK_Function
        // a down always counts, even after a lost release: comparing with the stored state would drop it
        if event.flags.contains(.maskSecondaryFn) {
            fnIsDown = true
            dictation.fnDown()
        } else if fnIsDown {
            fnIsDown = false
            dictation.fnUp()
        }
    case .keyDown, .keyUp:
        if type == .keyDown, dictation.phase == .arming { dictation.keyWhileArming() }  // Fn+F5: let it through
        // while dictating only the voice writes: keys are dropped (an early Enter would send the interim text and
        // the final fix-up would land in the emptied box); Esc cancels the dictation
        guard dictation.isActive else { break }
        if key == 53, type == .keyDown { dictation.escape() }  // kVK_Escape
        return nil
    default: break
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - App

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
    log("no Accessibility permission yet (System Settings → Privacy & Security → Device Control and Data Access)")
}

func installTap() {
    let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    // an active (.defaultTap) tap needs only Accessibility; a listen-only one would need Input Monitoring too
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil) else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { installTap() }  // no permission yet
        return
    }
    tap = t
    log("Accessibility trusted: \(AXIsProcessTrusted())")
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    log("Fn tap installed")
}

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Claude Dictate")
let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Hold Fn to speak · Esc cancels", action: nil, keyEquivalent: ""))
menu.addItem(.separator())
menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu

// quitting the app (menu, pkill, logout) takes the hidden claude down with it
let onTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
onTerm.setEventHandler { Mic.restore(); dictation.pty.stop(); exit(0) }
onTerm.resume()
NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
    Mic.restore()
    dictation.pty.stop()
}

Mic.restore()
installTap()
dictation.start()
app.run()
