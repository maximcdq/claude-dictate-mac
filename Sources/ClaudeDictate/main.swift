// ClaudeDictate: hold a key anywhere -> Claude Code /voice transcribes -> text is typed live into the focused field.
// Runs `claude --plugin-dir <state>/mod` in a hidden pty with DICTATE_STATE_DIR set; holding the hotkey streams spaces
// into it (what a held Space key looks like to a terminal app), the mod mirrors the prompt draft to
// <state>/live.txt, and this app types it into the focused field as it comes, fixing it up to the final text.
import AppKit
import DictateCore
import DictateUpdater

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
    log("no Accessibility permission yet (System Settings → Privacy & Security → Device Control and Data Access)")
}

let settings = SettingsStore.shared
let dictation = Dictation(settings: settings)
let hotkeyTap = HotkeyTap(dictation: dictation, settings: settings)

func shutDown() {
    Mic.restore()
    dictation.pty.stop()
}

let updater = Updater()
let updates = UpdateStatus(updater: updater)
updater.onChange = { updates.state = $0 }
updater.canInstall = { dictation.isIdle }
updater.onInstalled = { _ in relaunch(cleanup: shutDown) }
updater.setAutomatic(settings[.autoUpdate])
settings.observe(.autoUpdate) { updater.setAutomatic($0) }

var settingsWindow: SettingsWindow?
func showSettings() {
    if settingsWindow == nil { settingsWindow = SettingsWindow(settings: settings, updates: updates) }
    settingsWindow?.present()
}

let statusMenu = StatusMenu(settings: settings, openSettings: showSettings, checkForUpdates: {
    showSettings()
    updater.check()
})

// quitting the app (menu, pkill, logout) takes the hidden claude down with it
let onTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
onTerm.setEventHandler { shutDown(); exit(0) }
onTerm.resume()
NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
    shutDown()
}

// ask every app for its accessibility tree as it comes to the front, so it is built by the time the hotkey is held
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                  queue: .main) { _ in enableAppAccessibility() }

log("ClaudeDictate \(updater.currentVersion) starting")
Mic.restore()
hotkeyTap.install()
dictation.start()
app.run()
