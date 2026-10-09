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
                    Toggle("Drips", isOn: settings.binding(.drips))
                    Group {
                        Slider(value: settings.binding(.dripLength), in: 0.5...2) { Text("Length") }
                        Slider(value: settings.binding(.dripWidth), in: 0.5...2) { Text("Width") }
                        Slider(value: settings.binding(.dripCount), in: 1...9, step: 1) { Text("Count") }
                        Slider(value: settings.binding(.dripBlend), in: 0...1) { Text("Melt together") }
                    }
                    .disabled(!settings[.drips])
                    Slider(value: settings.binding(.dripGlow), in: 0...1) { Text("Glow") }
                    Picker("Result", selection: settings.binding(.resultPlace)) {
                        ForEach(NotchResultPlace.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Liquid Glass behind the result", isOn: settings.binding(.resultGlass))
                    Picker("Result color", selection: settings.binding(.resultColor)) {
                        ForEach(NotchResultColor.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(settings[.resultGlass])
                    Button("Preview") { NotchPreview.play(settings) }
                        .disabled(NotchIndicator.screen(anywhere: true) == nil)
                } header: {
                    Text("Notch")
                } footer: {
                    Text("Without drips only the glow shows. At the end the glow turns green when the text is typed, coral when nothing came; text that went to the clipboard brings out a clipboard icon, on Liquid Glass in the glass's own color or bare in the color you pick. Preview plays a few seconds of a made-up voice at the notch, then the result; the sliders change it as it plays.")
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
    private static var plays = 0  // each preview ends with the other result: a check, then a copy icon

    static func play(_ settings: SettingsStore) {
        let indicator = indicator ?? NotchIndicator(meter: Voice()) { settings.notchLook }
        indicator.menuBarAppearance = { StatusMenu.menuBarAppearance }
        Self.indicator = indicator
        guard indicator.show(anywhere: true) else { return }
        plays += 1
        let play = plays
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard plays == play else { return }
            indicator.process()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard plays == play else { return }
                indicator.done(play % 2 == 1 ? .typed : .copied)
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
