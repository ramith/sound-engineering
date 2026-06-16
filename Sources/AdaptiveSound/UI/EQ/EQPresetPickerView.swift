import SwiftUI

// MARK: - EQ Preset Picker

struct EQPresetPickerView: View {
    let eqViewModel: EQViewModel

    var body: some View {
        // Drive selection through a single path: the setter calls selectPreset
        // (which updates bandGains + dispatches once). Selecting a real preset
        // routes through there; the "Custom" tag is read-only — it reflects
        // canvas/slider edits, not a user choice — so its set is a no-op.
        // (Previously a direct binding + onChange mutated the model twice.)
        let selection = Binding<EQPreset?>(
            get: { eqViewModel.selectedPreset },
            set: { newPreset in
                if let preset = newPreset {
                    eqViewModel.selectPreset(preset)
                }
            }
        )

        Picker("Preset", selection: selection) {
            ForEach(EQPreset.allCases) { preset in
                Text(preset.displayName).tag(EQPreset?.some(preset))
            }
            Text("Custom").tag(EQPreset?.none)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("EQ Preset")
        .accessibilityValue(eqViewModel.selectedPresetName)
    }
}
