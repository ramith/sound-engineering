import SwiftUI

// MARK: - Output Device (Settings — S10.8 F2)

/// The Output Device card: the chrome's device pill (`OutputDevicePill` — the same picker, menu and
/// "checked" current device) beside the title, the device in use in detail, and whether playback stays
/// on it when another output connects. With no output device at all, it says so and offers neither.
struct OutputDeviceSettingsSection: View {
    @Bindable var audioViewModel: AudioViewModel

    var body: some View {
        SettingsCard(title: "Output Device") {
            if !audioViewModel.availableDevices.isEmpty {
                OutputDevicePill()
            }
        } content: {
            if audioViewModel.availableDevices.isEmpty {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                        .accessibilityHidden(true) // the text says it
                    Text("No output devices found")
                        .font(DesignSystem.Font.body)
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                }
            } else {
                // The rule parts the device from the switch, so it goes with the device: with none
                // selected, the switch sits right under the title.
                if let device = audioViewModel.selectedDevice {
                    DeviceDetailRow(device: device)
                    Hairline()
                }
                SettingsSwitchRow(title: "Keep playback on this device", detail: pinDetail,
                                  isOn: $audioViewModel.pinPlaybackToSelectedDevice)
            }
        }
    }

    /// What the switch does, in its current position.
    private var pinDetail: String {
        audioViewModel.pinPlaybackToSelectedDevice
            ? "Playback stays on the device you choose here and goes back to it when it reconnects. "
            + "Until you choose one, it follows your Mac’s sound output."
            : "Playback follows a newly connected device."
    }
}
