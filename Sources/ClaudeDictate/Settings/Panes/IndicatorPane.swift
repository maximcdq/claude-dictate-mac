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
        }
        .formStyle(.grouped)
    }
}
