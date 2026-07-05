import SwiftUI

/// Primary application toolbar (60pt).
///
/// Layout (left → right):
///   App logo squircle | Device dropdown pill | Tab selector | Spacer
///
/// The tab picker gets `.layoutPriority(1)` to prevent compression. The device
/// pill is width-bounded (minWidth…maxWidth) and truncates long names so an
/// aggregate-device name can't blow out the toolbar.
struct ToolbarView: View {
    @Environment(AudioViewModel.self) private var viewModel

    /// Binding to the tab selection owned by ContentView so the toolbar
    /// controls navigation without owning state it does not produce.
    @Binding var selectedTab: TabSelection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            AppLogoView()

            DevicePillView()

            TabSelectorView(selectedTab: $selectedTab, reduceMotion: reduceMotion)

            Spacer(minLength: 8)
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
                Button(action: { viewModel.selectDevice(device) }, label: {
                    if device.id == viewModel.selectedDevice?.id {
                        Label(device.displayName, systemImage: "checkmark")
                    } else {
                        Text(device.displayName)
                    }
                })
            }
        } label: {
            Label(
                viewModel.selectedDevice?.name ?? "No Device",
                systemImage: viewModel.selectedDevice?.systemIcon ?? "speaker.wave.2"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.asLabel)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 160, maxWidth: 240, minHeight: 32, alignment: .leading)
            .background(Color.asCard)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.asHairline, lineWidth: 0.5)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Audio output device")
        .accessibilityValue(viewModel.selectedDevice?.displayName ?? "No device selected")
        .accessibilityHint("Click to choose from available audio output devices")
    }
}

// MARK: - Tab Selector

private struct TabSelectorView: View {
    @Binding var selectedTab: TabSelection
    let reduceMotion: Bool

    var body: some View {
        Picker(
            selection: $selectedTab.animation(reduceMotion ? nil : .easeInOut(duration: 0.2))
        ) {
            ForEach(TabSelection.allCases, id: \.id) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
        } label: {
            EmptyView() // no picker label at all — the VoiceOver name comes from .accessibilityLabel below
        }
        .pickerStyle(.segmented)
        .layoutPriority(1)
        .accessibilityLabel("Tab Navigation")
        .accessibilityValue(selectedTab.rawValue)
    }
}
