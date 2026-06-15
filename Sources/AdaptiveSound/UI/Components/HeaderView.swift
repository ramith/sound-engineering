import SwiftUI

/// Fixed header component for AdaptiveSound
///
/// Displays a unified titlebar-respecting 44pt header with:
/// - Logo (music note icon)
/// - Device dropdown with selected device name and speaker icon
/// - Play/Stop button with SF Symbols
/// - Volume slider with percentage display
///
/// Layout: HStack with 4 sections, respecting macOS unified titlebar conventions
/// - 16pt horizontal margins
/// - 8pt gutters between elements
/// - All interactive elements >= 44x44pt (dropdown 40pt)
/// - Full accessibility labels and traits
struct FixedHeaderView: View {
    @EnvironmentObject var viewModel: AudioViewModel
    @State private var isPlaybackActive = false
    @State private var volume: Float = 0.75 // 0.0 to 1.0

    var body: some View {
        // MARK: - Fixed Header Container

        // 44pt height respecting macOS unified titlebar, transparent background
        HStack(spacing: 8) {
            // MARK: - Section 1: Logo

            // Music note icon (🎵) in a circular badge
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.asAccent)
                .frame(width: 44, height: 44)
                .accessibilityLabel("AdaptiveSound")
                .accessibilityHidden(true) // Redundant with header label

            // MARK: - Section 2: Device Dropdown

            // Displays selected device name with speaker icon + chevron
            // Responds to clicks to open device selection menu
            Menu {
                // Device selection menu items
                ForEach(viewModel.availableDevices, id: \.id) { device in
                    Button(action: { viewModel.selectDevice(device) }) {
                        HStack {
                            Text(device.displayName)
                            if device.id == viewModel.selectedDevice?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.asAccent)
                            }
                        }
                    }
                }
            } label: {
                // Dropdown button with selected device and chevron
                HStack(spacing: 6) {
                    Image(systemName: viewModel.selectedDevice?.systemIcon ?? "speaker.wave.2")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.asLabel)
                        .frame(width: 16, height: 16)

                    Text(viewModel.selectedDevice?.name ?? "No Device")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.asLabel)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.asLabelSecond)
                }
                .frame(height: 40)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .background(Color.asCard)
                .cornerRadius(8)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .frame(minWidth: 140)
            .accessibilityLabel("Audio device selector")
            .accessibilityValue(viewModel.selectedDevice?.displayName ?? "No device selected")
            .accessibilityHint("Click to select from available audio devices")

            // MARK: - Section 3: Play/Stop Button

            // Toggles playback state with SF Symbols (play.fill / stop.fill)
            // Minimum 44x44pt touch target
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPlaybackActive.toggle()
                }
            }) {
                Image(systemName: isPlaybackActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.asAccent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaybackActive ? "Stop playback" : "Start playback")
            .accessibilityHint(isPlaybackActive ? "Press to stop audio playback" : "Press to start audio playback")

            // MARK: - Section 4: Volume Slider

            // Displays volume percentage (0-100%) with horizontal slider
            // Minimum 44pt height with sufficient horizontal drag area
            HStack(spacing: 6) {
                // Volume percentage label
                Text("\(Int(volume * 100))%")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.asLabelSecond)
                    .frame(minWidth: 28, alignment: .trailing)

                // Slider with custom styling
                Slider(value: $volume, in: 0 ... 1)
                    .frame(minWidth: 80)
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(Int(volume * 100))%")
                    .accessibilityHint("Adjust audio output volume from 0 to 100 percent")
            }
            .frame(height: 44)
            .padding(.horizontal, 10)
            .background(Color.asCard)
            .cornerRadius(8)
        }

        // MARK: - Header Layout: Fixed 44pt height with margins and gutters

        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 0)
        .background(Color.asWindow)
        .overlay(
            // Subtle separator line at bottom
            VStack {
                Spacer()
                Divider()
                    .background(Color.asHairline)
            }
        )
    }
}
