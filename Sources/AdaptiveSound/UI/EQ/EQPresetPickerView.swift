import SwiftUI

// MARK: - EQ Preset Picker

/// A `.menu`-style picker that groups EQ presets by category.
///
/// Menu order (F6):
///   Group 1 — Analytic: Flat, Presence, Clarity, Warm
///   Group 2 — House curves: Loudness, Vocal, Studio
///   Divider
///   Custom (read-only; reflects canvas/slider edits)
///
/// Selecting a real preset routes through `EQViewModel.selectPreset`, which
/// updates `bandGains` and dispatches once. "Custom" is a read-only reflection
/// tag — its setter is intentionally a no-op.
struct EQPresetPickerView: View {
    let eqViewModel: EQViewModel

    // MARK: - Named preset groups (F6)

    private static let analyticPresets: [EQPreset] = [.flat, .presence, .clarity, .warm]
    private static let housePresets: [EQPreset] = [.loudness, .vocal, .studio]

    var body: some View {
        let selection = Binding<EQPreset?>(
            get: { eqViewModel.selectedPreset },
            set: { newPreset in
                if let preset = newPreset {
                    eqViewModel.selectPreset(preset)
                }
            }
        )

        Picker("Preset", selection: selection) {
            ForEach(Self.analyticPresets) { preset in
                Text(preset.displayName).tag(EQPreset?.some(preset))
            }

            Divider()

            ForEach(Self.housePresets) { preset in
                Text(preset.displayName).tag(EQPreset?.some(preset))
            }

            Divider()

            Text("Custom").tag(EQPreset?.none)
        }
        .pickerStyle(.menu)
        .accessibilityLabel("EQ Preset")
        .accessibilityValue(eqViewModel.selectedPresetName)
    }
}
