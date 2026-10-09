import DictateAnimations
import DictateCore
import SwiftUI

struct IndicatorPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("While dictating, show") {
                Picker("Indicator", selection: settings.binding(.indicator)) {
                    ForEach(IndicatorStyle.allCases) { style in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title)
                            Text(style.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            if settings[.indicator] == .notch {
                Section {
                    Slider(value: settings.binding(.dripSize), in: 0.5...2) { Text("Size") }
                    Slider(value: settings.binding(.dripGlow), in: 0...1) { Text("Glow") }
                    Slider(value: settings.binding(.dripCount), in: 1...9, step: 1) { Text("Drips") }
                    Button("Preview") { NotchPreview.play(settings) }
                        .disabled(NotchIndicator.screen(anywhere: true) == nil)
                } header: {
                    Text("Drips")
                } footer: {
                    Text("Preview plays a few seconds of a made-up voice at the notch; the sliders change it as it plays.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// The drips at the notch with a voice that comes and goes, for trying the sliders.
enum NotchPreview {
    private static var indicator: NotchIndicator?
    private static var plays = 0

    static func play(_ settings: SettingsStore) {
        let indicator = indicator ?? NotchIndicator(meter: Voice()) { settings.notchLook }
        Self.indicator = indicator
        guard indicator.show(anywhere: true) else { return }
        plays += 1
        let play = plays
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard plays == play else { return }
            indicator.process()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard plays == play else { return }
                indicator.done(empty: false)
            }
        }
    }

    // words and pauses: a level that swells and drops a few times a second, with a short silence now and then
    private final class Voice: LevelSource {
        private var startedAt = Date()
        var heardAt: Date? { startedAt }
        var level: CGFloat {
            let t = Date().timeIntervalSince(startedAt)
            guard t.truncatingRemainder(dividingBy: 2.4) < 1.7 else { return 0.05 }
            return CGFloat(0.35 + 0.3 * abs(sin(t * 5.3)) * abs(sin(t * 1.7 + 1)))
        }
        func start() { startedAt = Date() }
        func stop() {}
        func watch() {}
    }
}
