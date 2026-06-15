import SwiftUI

/// Fixed header component for AdaptiveSound
///
/// Displays a unified titlebar-respecting header with:
/// - Logo (music note icon)
/// - Device dropdown (native Menu popup button)
/// - Play/Stop button (native .borderedProminent)
/// - Volume slider with percentage display
///
/// Layout: HStack with 4 sections, respecting macOS unified titlebar conventions.
struct FixedHeaderView: View {
    @EnvironmentObject var viewModel: AudioViewModel
    @State private var isPlaybackActive = false
    @State private var volume: Float = 0.75 // 0.0 to 1.0

    var body: some View {
        HStack(spacing: 8) {
            // MARK: - Section 1: Logo

            Image(systemName: "music.note")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.asAccent)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            // MARK: - Section 2: Device Dropdown (native Menu popup button)

            Menu {
                ForEach(viewModel.availableDevices, id: \.id) { device in
                    Button(action: { viewModel.selectDevice(device) }) {
                        if device.id == viewModel.selectedDevice?.id {
                            Label(device.displayName, systemImage: "checkmark")
                        } else {
                            Text(device.displayName)
                        }
                    }
                }
            } label: {
                Label(
                    viewModel.selectedDevice?.name ?? "No Device",
                    systemImage: viewModel.selectedDevice?.systemIcon ?? "speaker.wave.2"
                )
            }
            .frame(minWidth: 140)
            .accessibilityLabel("Audio device selector")
            .accessibilityValue(viewModel.selectedDevice?.displayName ?? "No device selected")
            .accessibilityHint("Click to select from available audio devices")

            // MARK: - Section 3: Play/Stop Button (native bordered prominent)

            Button(action: togglePlayback) {
                Label(
                    isPlaybackActive ? "Stop" : "Play",
                    systemImage: isPlaybackActive ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityLabel(isPlaybackActive ? "Stop playback" : "Start playback")
            .accessibilityHint(isPlaybackActive ? "Press to stop audio playback" : "Press to start audio playback")

            // MARK: - Section 4: Volume Slider

            HStack(spacing: 6) {
                Text("\(Int(volume * 100))%")
                    .font(.callout.monospaced())
                    .foregroundStyle(Color.asLabelSecond)
                    .frame(minWidth: 36, alignment: .trailing)

                Slider(value: $volume, in: 0 ... 1)
                    .frame(minWidth: 80)
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(Int(volume * 100))%")
                    .accessibilityHint("Adjust audio output volume from 0 to 100 percent")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.asCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .background(Color.asWindow)
        .overlay(alignment: .bottom) {
            Divider()
                .background(Color.asHairline)
        }
    }

    // MARK: - Actions

    private func togglePlayback() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPlaybackActive.toggle()
        }
    }
}
