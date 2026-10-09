import AppKit

// Opening the app again (Finder, Spotlight, `open`, its Dock icon) brings up Settings: the way back in when the menu
// bar icon is hidden (System Settings → Menu Bar). While the app is in the Dock it has a menu bar of its own, so
// ⌘, ⌘H ⌘W and ⌘Q work as in any app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    @objc private func settingsPicked() { openSettings() }

    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsPicked), keyEquivalent: ",")
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide ClaudeDictate", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit ClaudeDictate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        for (title, menu) in [("ClaudeDictate", appMenu), ("Window", windowMenu)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.windowsMenu = windowMenu
        return main
    }
}
