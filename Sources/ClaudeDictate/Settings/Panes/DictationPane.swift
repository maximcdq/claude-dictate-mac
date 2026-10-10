import DictateCore
import SwiftUI

struct DictationPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: settings.binding(.language)) {
                    Text("Same as Claude Code").tag("")
                    Divider()
                    ForEach(dictationLanguages, id: \.code) { Text($0.name).tag($0.code) }
                }
            } footer: {
                Text("“Same as Claude Code” follows the `language` setting in ~/.claude/settings.json (English when unset). Changing it restarts the hidden Claude Code session: dictation is ready again in a few seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Record with the built-in microphone", isOn: settings.binding(.builtInMic))
            } footer: {
                Text("While dictating, the Mac's own mic becomes the input, so AirPods keep their high-quality audio; the previous input comes back afterwards. Off: the system's default input is used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Pause music and videos while dictating", isOn: settings.binding(.pauseMedia))
            } footer: {
                Text("Whatever is playing (Music, Spotify, a video in the browser) pauses when the dictation begins and plays on when it ends. Nothing starts that wasn't playing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
