import SwiftUI

struct SettingsTabView: View {
    @Environment(AudioViewModel.self) private var audioViewModel

    var body: some View {
        @Bindable var vm = audioViewModel

        VStack(spacing: 24) {
            // MARK: Output Device Section

            VStack(alignment: .leading, spacing: 8) {
                Text("Output Device")
                    .font(.headline)
                    .foregroundStyle(Color.asLabel)
                    .padding(.horizontal, 16)

                if audioViewModel.availableDevices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.asLabelTertiary)
                        Text("No output devices found")
                            .font(.body)
                            .foregroundStyle(Color.asLabelTertiary)
                    }
                    .padding(.horizontal, 16)
                } else {
                    Picker("Output Device", selection: $vm.selectedDevice) {
                        Text("None")
                            .tag(AudioDeviceModel?.none)
                        ForEach(audioViewModel.availableDevices) { device in
                            HStack(spacing: 6) {
                                Image(systemName: device.systemIcon)
                                Text("\(device.name)  \(device.displayKHz)")
                            }
                            .tag(Optional(device))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 16)
                    .onChange(of: audioViewModel.selectedDevice) { _, newDevice in
                        if let device = newDevice {
                            audioViewModel.selectDevice(device)
                        }
                    }

                    // Show current device details
                    if let device = audioViewModel.selectedDevice {
                        DeviceDetailRow(device: device)
                            .padding(.horizontal, 16)
                    }

                    Toggle(isOn: $vm.pinPlaybackToSelectedDevice) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep playback on this device")
                                .font(.body)
                                .foregroundStyle(Color.asLabel)
                            Text(audioViewModel.pinPlaybackToSelectedDevice
                                ? "Connecting headphones or a Bluetooth device won't move playback — switch to it here."
                                : "Playback follows a newly-connected device.")
                                .font(.caption)
                                .foregroundStyle(Color.asLabelTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, 16)
                }
            }

            Divider()
                .padding(.horizontal, 16)

            // MARK: Pure Mode (bit-perfect HAL) — interim B3 smoke-test control (A2 = polished UI)

            PureModeSettingsSection(audioViewModel: audioViewModel)

            Divider()
                .padding(.horizontal, 16)

            // MARK: Future Settings (placeholder)

            VStack(spacing: 12) {
                Text("Coming in Phase 1b")
                    .font(.body)
                    .foregroundStyle(Color.asLabelSecond)
                    .padding(.top, 8)

                SettingsControlRow(
                    title: "Hearing Profile",
                    icon: "ear.fill"
                )

                SettingsControlRow(
                    title: "Device Correction EQ",
                    icon: "slider.horizontal.3"
                )

                SettingsControlRow(
                    title: "Loudness Compensation",
                    icon: "speaker.wave.2.fill"
                )

                SettingsControlRow(
                    title: "About/Help",
                    icon: "questionmark.circle.fill"
                )
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }
}

// MARK: - Device Detail Row

/// Private to this file — only used inline within SettingsTabView.
private struct DeviceDetailRow: View {
    let device: AudioDeviceModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.systemIcon)
                .font(.body)
                .foregroundStyle(Color.asAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.body)
                    .foregroundStyle(Color.asLabel)
                Text("ID \(device.id)  •  \(device.displayKHz)  •  \(device.bufferFrameSize) frames")
                    .font(.caption)
                    .foregroundStyle(Color.asLabelTertiary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.asCard)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5)
        }
    }
}
