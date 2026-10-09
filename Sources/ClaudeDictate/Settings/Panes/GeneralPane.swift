import DictateCore
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var startAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                Picker("Hold to dictate", selection: settings.binding(.hotkey)) {
                    ForEach(Hotkey.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold the key in any text field and speak; release it to finish. Esc cancels. A tap, or the key with another one (a shortcut), works as usual.")
                    if settings[.hotkey] == .fn {
                        Text("Set System Settings → Keyboard → “Press 🌐 key to” to “Do Nothing”, or macOS opens its own dictation or the emoji picker.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Start at login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, on in LoginItem.isEnabled = on }
            }
            Section {
                Toggle("Keep in the Dock", isOn: settings.binding(.keepInDock))
            } footer: {
                Text("Off: ClaudeDictate shows in the Dock only while Settings is open and keeps working in the background when you close it. Open the app again (Finder, Spotlight) to get back here, also with its menu bar icon hidden in System Settings → Menu Bar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
