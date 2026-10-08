import AppKit
import DictateCore
import DictateUpdater
import SwiftUI

struct UpdatesPane: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var updates: UpdateStatus

    var body: some View {
        Form {
            Section {
                Toggle("Install updates automatically", isOn: settings.binding(.autoUpdate))
                LabeledContent("Version", value: updates.updater.currentVersion)
                LabeledContent("Status") {
                    HStack {
                        Text(status).foregroundStyle(.secondary)
                        Button("Check Now") { updates.updater.check() }
                            .disabled(busy)
                    }
                }
            } footer: {
                Text("New releases come from GitHub. An update installs while you're not dictating and restarts the app; permissions stay granted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Source") {
                    Link("github.com/maximcdq/claude-dictate-mac", destination: URL(string: "https://github.com/maximcdq/claude-dictate-mac")!)
                }
                LabeledContent("Log") {
                    Button("Show in Finder") { NSWorkspace.shared.selectFile(Paths.log, inFileViewerRootedAtPath: "") }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var busy: Bool {
        switch updates.state {
        case .checking, .installing, .installed: true
        default: false
        }
    }

    private var status: String {
        switch updates.state {
        case .idle: "—"
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .installing(let v): "Installing \(v)…"
        case .installed(let v): "Restarting into \(v)…"
        case .failed(let message): message
        }
    }
}
