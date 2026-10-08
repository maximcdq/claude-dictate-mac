import AppKit
import DictateCore
import DictateUpdater

// The menu bar item: the hint for the hotkey, the settings, updates, quit.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: SettingsStore
    private let hint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let openSettings: () -> Void
    private let checkForUpdates: () -> Void

    init(settings: SettingsStore, openSettings: @escaping () -> Void, checkForUpdates: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        super.init()
        item.button?.image = MenuBarIcon.image()
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(action("Settings…", #selector(settingsPicked), key: ","))
        menu.addItem(action("Check for Updates…", #selector(updatesPicked)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ClaudeDictate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        hint.title = "Hold \(settings[.hotkey].shortTitle) to speak · Esc cancels"
    }

    @objc private func settingsPicked() { openSettings() }
    @objc private func updatesPicked() { checkForUpdates() }
}
