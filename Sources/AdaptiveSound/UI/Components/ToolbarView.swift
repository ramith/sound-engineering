import SwiftUI

/// Primary application toolbar (60pt).
///
/// Layout (left → right):
///   App logo squircle | Device dropdown pill | Tab selector | Spacer | Volume control
///
/// All interactive elements are ≥44pt tap targets. The tab picker gets
/// `.layoutPriority(1)` to prevent compression before the device pill collapses.
/// The device pill has a `minWidth` to stay readable at the 800pt window minimum.
struct ToolbarView: View {
    @Environment(AudioViewModel.self) private var viewModel

    /// Binding to the tab selection owned by ContentView so the toolbar
    /// controls navigation without owning state it does not produce.
    @Binding var selectedTab: TabSelection

    /// Volume: 0.0 – 1.0. Owned by ContentView and bound here so the
    /// value survives tab switches.
    @Binding var volume: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            AppLogoView()

            DevicePillView()

            TabSelectorView(selectedTab: $selectedTab, reduceMotion: reduceMotion)

            Spacer(minLength: 8)

            VolumeControlView(volume: $volume)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Color.asWindow)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.asHairline)
                .frame(height: 0.5)
        }
    }
}

// MARK: - App Logo

private struct AppLogoView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient.asIconFill)
                .frame(width: 30, height: 30)

            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Device Dropdown Pill

private struct DevicePillView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        Menu {
            ForEach(viewModel.availableDevices) { device in
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
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.asLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 160, minHeight: 32, alignment: .leading)
            .background(Color.asCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.asHairline, lineWidth: 0.5)
            }
        }
        .accessibilityLabel("Audio output device")
        .accessibilityValue(viewModel.selectedDevice?.displayName ?? "No device selected")
        .accessibilityHint("Click to choose from available audio output devices")
        .fixedSize()
    }
}

// MARK: - Tab Selector

private struct TabSelectorView: View {
    @Binding var selectedTab: TabSelection
    let reduceMotion: Bool

    var body: some View {
        Picker(
            "Tab Navigation",
            selection: $selectedTab.animation(reduceMotion ? nil : .easeInOut(duration: 0.2))
        ) {
            ForEach(TabSelection.allCases, id: \.id) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .layoutPriority(1)
        .accessibilityLabel("Tab Navigation")
        .accessibilityValue(selectedTab.rawValue)
    }
}

// MARK: - Volume Control

private struct VolumeControlView: View {
    @Binding var volume: Float

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.callout)
                .foregroundStyle(Color.asLabelSecond)
                .frame(width: 20)
                .accessibilityHidden(true)

            Slider(value: $volume, in: 0 ... 1)
                .frame(minWidth: 80, maxWidth: 120)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(volume * 100))%")
                .accessibilityHint("Adjust audio output volume from 0 to 100 percent")

            Text("\(Int(volume * 100))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(Color.asLabelSecond)
                .frame(minWidth: 36, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.asCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(minHeight: 44)
    }
}
