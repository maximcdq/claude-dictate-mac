import AppKit
import DictateCore
import DictateUpdater
import SwiftUI

// A pane of the settings window: one toolbar tab. To add a pane, write its SwiftUI view in Panes/ and list it in
// SettingsWindow.panes.
struct SettingsPane {
    let title: String
    let symbol: String
    let view: AnyView
}

// The settings window: a toolbar of tabs, each a grouped form, as in System Settings-era macOS apps.
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    var onClose: () -> Void = {}

    init(settings: SettingsStore, updates: UpdateStatus) {
        let panes = [
            SettingsPane(title: "General", symbol: "gearshape", view: AnyView(GeneralPane())),
            SettingsPane(title: "Dictation", symbol: "waveform", view: AnyView(DictationPane())),
            SettingsPane(title: "Indicator", symbol: "sparkles", view: AnyView(IndicatorPane())),
            SettingsPane(title: "Updates", symbol: "arrow.triangle.2.circlepath", view: AnyView(UpdatesPane())),
        ]
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in panes {
            let host = NSHostingController(rootView: pane.view
                .environmentObject(settings)
                .environmentObject(updates)
                .frame(width: 480)
                .fixedSize())
            host.sizingOptions = [.preferredContentSize]
            host.title = pane.title  // the window takes the selected tab's title, as System Settings-era apps do
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func present() {
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// The updater's state for the Updates pane.
final class UpdateStatus: ObservableObject {
    let updater: Updater
    @Published var state = Updater.State.idle

    init(updater: Updater) {
        self.updater = updater
    }
}

extension SettingsStore {
    func binding<Value>(_ setting: Setting<Value>) -> Binding<Value> {
        Binding(get: { self[setting] }, set: { self[setting] = $0 })
    }
}
