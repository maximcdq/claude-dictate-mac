import AppKit
import DictateCore

// Restart into the app bundle on disk (after an update). Under the launchd agent a failing exit is restarted by
// launchd itself (KeepAlive: SuccessfulExit false); started any other way, a detached `open` brings it back.
func relaunch(cleanup: () -> Void) {
    cleanup()
    if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == appLabel {
        log("restarting through launchd")
        exit(75)  // EX_TEMPFAIL
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
    try? p.run()
    log("restarting through open")
    exit(0)
}
