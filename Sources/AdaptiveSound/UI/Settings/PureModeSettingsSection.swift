import SwiftUI

/// The Pure Mode card (bit-perfect HAL output): a switch for user intent plus a live signal-path
/// readout (polled into `AudioViewModel.signalPath` at the spectrum-timer rate). The switch records
/// intent only; it takes effect on the next track / play.
struct PureModeSettingsSection: View {
    @Bindable var audioViewModel: AudioViewModel

    /// The EQ as it plays ("Warm · edited" / "Off"), threaded in from the parent view so the card
    /// remains a pure value-snapshot read (consistent with the F4 pattern). The parent
    /// reads this from `EQViewModel.summary` via its own Environment access.
    let eqPresetName: String

    var body: some View {
        SettingsCard(title: "Pure Mode (Bit-Perfect)") {
            SettingsSwitchRow(title: "Bit-perfect HAL output",
                              detail: "DSP/EQ bypassed, bit-perfect HAL output, per-track rate match. "
                                  + "Applies on the next track / play.",
                              isOn: $audioViewModel.pureModeEnabled)
            Hairline()
            SignalPathStatus(
                info: audioViewModel.signalPath,
                requested: audioViewModel.pureModeEnabled,
                eqPresetName: eqPresetName
            )
        }
    }
}
