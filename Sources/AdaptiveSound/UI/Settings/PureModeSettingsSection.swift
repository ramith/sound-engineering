import SwiftUI

/// The Pure Mode card (bit-perfect HAL output): a switch for user intent plus a live signal-path
/// readout (polled into `AudioViewModel.signalPath` at the spectrum-timer rate). The switch records
/// intent only; it takes effect the next time a song is started — not at a gapless join (KI-PB-05).
struct PureModeSettingsSection: View {
    @Bindable var audioViewModel: AudioViewModel

    /// The EQ as it plays ("Warm · edited" / "Off"), threaded in from the parent view so the card
    /// remains a pure value-snapshot read (consistent with the F4 pattern). The parent
    /// reads this from `EQViewModel.summary` via its own Environment access.
    let eqPresetName: String

    var body: some View {
        SettingsCard(title: "Pure Mode (Bit-Perfect)") {
            SettingsSwitchRow(title: "Play bit-perfect",
                              detail: "Sends each track to your device untouched: no EQ or effects, and the "
                                  + "device follows the track’s sample rate. Takes effect the next time you "
                                  + "start a song.",
                              isOn: $audioViewModel.pureModeEnabled)
            Hairline()
            SignalPathStatus(
                info: audioViewModel.signalPath,
                requested: audioViewModel.pureModeEnabled,
                masterGain: audioViewModel.masterGain,
                eqPresetName: eqPresetName
            )
        }
    }
}
