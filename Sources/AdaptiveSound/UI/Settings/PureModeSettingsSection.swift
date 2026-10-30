import SwiftUI

/// The Pure Mode card (bit-perfect HAL output): a switch for user intent plus a live signal-path
/// readout (polled into `AudioViewModel.signalPath` at the spectrum-timer rate). The switch records
/// intent only; it takes effect the next time a song is started — not at a gapless join (KI-PB-05).
/// Under the switch, one sentence on why there are two untouched states (R1.1-B, US-R1F-20 item 3).
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
            Text(Self.twoUntouchedStates)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Hairline()
            SignalPathStatus(
                info: audioViewModel.signalPath,
                requested: audioViewModel.pureModeEnabled,
                masterGain: audioViewModel.masterGain,
                eqPresetName: eqPresetName
            )
        }
    }

    /// Why Pure and Enhanced-with-nothing-on are both "untouched", and what the engine buys (US-R1F-20 item 3).
    static let twoUntouchedStates = "Pure sends the file to your device untouched; Enhanced with every effect off "
        + "leaves the sound untouched too, but plays through the app’s engine, which is what lets leveling, "
        + "surround folding and the effects work."
}
