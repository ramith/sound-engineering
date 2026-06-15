import SwiftUI

// MARK: - EQ Preset Picker

struct EQPresetPickerView: View {
    let eqViewModel: EQViewModel

    var body: some View {
        // Using @Bindable inline because EQViewModel is passed as a let constant.
        // We need a Bindable wrapper to create a binding from an @Observable class.
        let bindable = Bindable(eqViewModel)

        Picker("Preset", selection: bindable.selectedPreset) {
            ForEach(EQPreset.allCases) { preset in
                Text(preset.displayName).tag(EQPreset?.some(preset))
            }
            Text("Custom").tag(EQPreset?.none)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("EQ Preset")
        .accessibilityValue(eqViewModel.selectedPresetName)
        .onChange(of: eqViewModel.selectedPreset) { _, newPreset in
            if let preset = newPreset {
                eqViewModel.selectPreset(preset)
            }
        }
    }
}
