import EQEditKit
import SwiftUI

// MARK: - EQ Preset Picker

/// A `.menu`-style picker that groups EQ presets by category.
///
/// Menu order (F6):
///   Group 1 — Analytic: Flat, Presence, Clarity, Warm
///   Group 2 — House curves: Loudness, Vocal, Studio
///   Divider
///   The EQ's own line (read-only), when it isn't an unedited built-in: "Warm · edited", a saved
///   preset's name
///
/// Choosing a built-in routes through `EQViewModel.choose`, which applies it and sends it once;
/// choosing the built-in already shown edited resets it. The read-only line's setter is a no-op.
struct EQPresetPickerView: View {
    let eqViewModel: EQViewModel

    // MARK: - Named preset groups (F6)

    private static let analyticPresets: [EQBuiltInPreset] = [.flat, .presence, .clarity, .warm]
    private static let housePresets: [EQBuiltInPreset] = [.loudness, .vocal, .studio]

    /// The built-in the EQ plays unedited; `nil` for an edit or a saved preset.
    private var uneditedBuiltIn: EQBuiltInPreset? {
        guard case let .builtIn(preset) = eqViewModel.current.preset, !eqViewModel.isEdited else { return nil }
        return preset
    }

    var body: some View {
        let selection = Binding<EQBuiltInPreset?>(
            get: { uneditedBuiltIn },
            set: { newPreset in
                if let preset = newPreset {
                    eqViewModel.choose(.builtIn(preset))
                }
            }
        )

        Picker("Preset", selection: selection) {
            ForEach(Self.analyticPresets) { preset in
                Text(preset.displayName).tag(EQBuiltInPreset?.some(preset))
            }

            Divider()

            ForEach(Self.housePresets) { preset in
                Text(preset.displayName).tag(EQBuiltInPreset?.some(preset))
            }

            if uneditedBuiltIn == nil {
                Divider()

                Text(eqViewModel.presetLabel).tag(EQBuiltInPreset?.none)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden() // the parent LabeledContent("Preset") supplies the VoiceOver label
        .accessibilityValue(eqViewModel.presetLabel)
    }
}
