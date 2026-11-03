import AppKit
import DictateCore
import Security

// When Claude Code's login last changed: the date on its Keychain item, read without touching the token. A running
// session does not pick up a new /login by itself.
func claudeLoginStamp() -> Date? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "Claude Code-credentials",
                                kSecMatchLimit as String: kSecMatchLimitOne,
                                kSecReturnAttributes as String: true]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
    return (item as? [String: Any])?[kSecAttrModificationDate as String] as? Date
}

// the newest real binary of the native install: ~/.local/bin/claude is a wrapper script that puts claude in a pty
// of its own, which would leave it orphaned (and out of our process group) when the app quits; other installs
// (Homebrew, npm) are found on the usual paths
func claudeBinary(avoiding failed: Set<String> = []) -> String {
    if let version = claudeVersion(in: "\(Paths.home)/.local/share/claude/versions", avoiding: failed) { return version }
    let fm = FileManager.default
    let found = ["\(Paths.home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(Paths.home)/.npm-global/bin"]
        .map { "\($0)/claude" }.first { fm.isExecutableFile(atPath: $0) }
    return found.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } ?? "\(Paths.home)/.local/bin/claude"
}

// MARK: - Claude Code in a hidden pty

final class ClaudePty {
    private(set) var master: Int32 = -1
    private var pid: pid_t = 0
    private var reader: DispatchSourceRead?
    private var exitWatch: DispatchSourceProcess?
    private var retry: DispatchWorkItem?  // the next start, after a failed one or an exit
    private var bin = ""  // the Claude Code this session runs
    // versions that would not start or never gave voice: the next start takes the one before, so a broken Claude Code
    // update leaves dictation on the previous version
    private var failed: Set<String> = []
    private var killing = false  // the coming exit is a restart of ours, not claude quitting
    private var startedAt = Date()
    private var trustAnswered = false
    private var tail = ""
    private(set) var lastProcessingAt = Date.distantPast
    private(set) var lastNoSpeechAt = Date.distantPast
    private(set) var lastVoiceAt = Date.distantPast  // /voice took the held Space as hold-to-talk
    var isReady: Bool { Date().timeIntervalSince(startedAt) > 8 }
    var language: () -> String = { "" }  // the dictation language; empty follows the user's Claude Code settings

    // a hard crash of the app leaves its claude running; the next start finishes it off
    private let pidFile = "\(Paths.state)/claude.pid"

    private func killLeftover() {
        guard let old = (try? String(contentsOfFile: pidFile, encoding: .utf8)).flatMap({ pid_t($0) }), old > 0 else { return }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(old, &path, UInt32(path.count)) > 0, String(cString: path).contains("/claude/versions/") {
            kill(-old, SIGKILL)
            log("killed leftover claude \(old)")
        }
    }

    func start() {
        retry?.cancel()
        retry = nil
        killLeftover()
        var m: Int32 = 0, s: Int32 = 0
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&m, &s, nil, nil, &size) == 0 else { log("openpty failed, retrying in 5 s"); return startAgain(after: 5) }
        let slavePath = String(cString: ptsname(m))
        close(s)
        master = m

        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        for fd: Int32 in 0...2 { posix_spawn_file_actions_addopen(&fa, fd, slavePath, O_RDWR, 0) }
        posix_spawn_file_actions_addchdir(&fa, Paths.agent)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        // drop markers of whatever claude session launched this app, or the child thinks it is a subsession
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CLAUDE_CODE") && $0.key != "CLAUDECODE" }
        env["DICTATE_STATE_DIR"] = Paths.state
        env["TERM"] = "xterm-256color"
        env["PATH"] = "\(Paths.home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // updates are left to the user's own sessions: this one gets killed on a restart, also in the middle of one
        env["DISABLE_AUTOUPDATER"] = "1"
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        bin = claudeBinary(avoiding: failed)
        // --strict-mcp-config: this session never runs a tool, so the user's MCP servers would only start and sit in memory
        let args: [String] = [bin, "--plugin-dir", Paths.mod, "--settings", sessionSettings(), "--strict-mcp-config"]
        let argv = args.map { strdup($0) } + [nil]
        defer { (envp + argv).forEach { free($0) } }

        try? FileManager.default.createDirectory(atPath: Paths.agent, withIntermediateDirectories: true)
        let rc = posix_spawn(&pid, bin, &fa, &attr, argv, envp)
        posix_spawn_file_actions_destroy(&fa)
        posix_spawnattr_destroy(&attr)
        // without a session no dictation works: try again, with the version before this one
        guard rc == 0 else {
            log("spawn failed: \(rc) (\(bin)), retrying in 5 s")
            failed.insert(bin)
            close(m)
            master = -1
            pid = 0
            return startAgain(after: 5)
        }
        startedAt = Date()
        trustAnswered = false
        try? "\(pid)".write(toFile: pidFile, atomically: true, encoding: .utf8)
        log("claude started, pid \(pid): \(bin)")

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
            // quit on its own before it was ready: this version does not run here
            if !self.killing, !self.isReady { self.failed.insert(self.bin) }
            self.killing = false
            self.reader?.cancel()
            self.exitWatch?.cancel()
            close(self.master)
            self.master = -1
            self.pid = 0
            self.startAgain(after: 2)
        }
        w.resume()
        exitWatch = w
    }

    // a restart() in the meantime starts at once instead
    private func startAgain(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.start() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // voice is off in the user's settings (Space types spaces in their sessions); this session turns it on
    private func sessionSettings() -> String {
        var settings: [String: Any] = ["voiceEnabled": true, "voice": ["enabled": true, "mode": "hold"]]
        let language = language()
        if !language.isEmpty { settings["language"] = language }
        let json = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        return json.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
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
        if text.contains("keep holding") || text.contains("listening") { lastVoiceAt = Date() }
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

    // a fresh session with the current settings: the exit watch starts it again; not ready until it has.
    // `versionFailed`: this version did not work, the new session runs the one before it.
    func restart(because reason: String = "new settings or login", versionFailed: Bool = false) {
        if versionFailed { failed.insert(bin) }
        guard pid > 0 else { return start() }
        startedAt = Date()
        killing = true
        log("restarting claude: \(reason)")
        kill(-pid, SIGKILL)
    }

    // with a new login the versions that failed may work again
    func loginChanged() { failed = [] }

    func write(_ s: String) {
        guard master >= 0 else { return }
        _ = s.withCString { Darwin.write(master, $0, strlen($0)) }
    }
}

// The mod ships inside the app bundle and runs from the state folder: Claude Code writes type stubs next to a plugin,
// which would break the bundle's seal. Copied fresh at every launch, so an updated app brings its own mod.
func installMod() {
    guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("mod"),
          FileManager.default.fileExists(atPath: bundled.path) else { return log("mod: none in the bundle, keeping \(Paths.mod)") }
    let fm = FileManager.default
    try? fm.createDirectory(atPath: Paths.state, withIntermediateDirectories: true)
    try? fm.removeItem(atPath: Paths.mod)
    do { try fm.copyItem(at: bundled, to: URL(fileURLWithPath: Paths.mod)) } catch { log("mod: copy failed: \(error)") }
}
