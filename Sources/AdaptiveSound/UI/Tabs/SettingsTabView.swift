import SwiftUI

struct SettingsTabView: View {
    @Environment(AudioViewModel.self) private var audioViewModel
    @Environment(EQViewModel.self) private var eqViewModel

    var body: some View {
        @Bindable var bindVM = audioViewModel

        // Screen(.stack) scrolls on a short window (fixes bug 4 — Settings clipped its lower
        // sections) and top-aligns/fills within the shell's bounded region. edgeToEdge keeps the
        // sections' own horizontal padding rather than doubling it with Screen's insets.
        Screen(mode: .stack, edgeToEdge: true) {
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
                        // Commit-on-success binding (UI-1), mirroring the toolbar device pill: the
                        // setter routes through selectDevice(), which persists `selectedDevice` ONLY
                        // when the switch succeeds. The getter always reflects the actual active device,
                        // so a FAILED switch leaves the picker on the previous device (auto-revert) —
                        // it never pre-commits the way a plain two-way binding + onChange did.
                        Picker("Output Device", selection: Binding(
                            get: { audioViewModel.selectedDevice },
                            set: { newDevice in
                                if let device = newDevice { audioViewModel.selectDevice(device) }
                            }
                        )) {
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

                        // Show current device details
                        if let device = audioViewModel.selectedDevice {
                            DeviceDetailRow(device: device)
                                .padding(.horizontal, 16)
                        }

                        Toggle(isOn: $bindVM.pinPlaybackToSelectedDevice) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep playback on this device")
                                    .font(.body)
                                    .foregroundStyle(Color.asLabel)
                                Text(audioViewModel.pinPlaybackToSelectedDevice
                                    ? "Connecting headphones or a Bluetooth device won't move "
                                    + "playback — switch to it here."
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

                // MARK: Pure Mode (bit-perfect HAL)

                PureModeSettingsSection(
                    audioViewModel: audioViewModel,
                    eqPresetName: eqViewModel.selectedPresetName
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
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
