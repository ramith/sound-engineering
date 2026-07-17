import SwiftUI

/// The app-owned chrome header (the shell's top band).
///
/// Layout (left → right):
///   App logo squircle | Device dropdown pill | Tab selector | Spacer
///
/// `AppShell` owns the band height (`ShellMetrics.chromeHeight`), the window background,
/// and the bottom hairline, so this view sets none of those. Its leading edge shares the
/// content's left margin — with the native titlebar restored, the window buttons sit in their
/// own strip, so no traffic-light inset is needed.
///
/// The tab picker is `.fixedSize()` (locked to its intrinsic size — never stretches or
/// compresses). The device pill is fixed-width and truncates long names, so the tab control's
/// left edge is invariant to the device name and an aggregate-device name can't blow out the header.
struct ChromeBar: View {
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
        // Shares the content's leading margin: with the native titlebar restored, the window
        // buttons live in their own strip, so the chrome no longer insets to clear them — its
        // left edge lines up with the content below. Height, window background, and the bottom
        // hairline are owned by AppShell — deliberately not set here.
        .padding(.horizontal, 16)
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
                .foregroundStyle(DesignSystem.Color.onAccent)
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
            // Fixed width (minWidth == maxWidth), not a range: the pill's width was tracking the
            // device NAME, which slid the tab control's left edge on every device change. Fixed →
            // tabs' x-origin is invariant (the founder's "fixed top-left"). Long names truncate.
            .frame(minWidth: 200, maxWidth: 200, minHeight: 32, alignment: .leading)
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
        // Lock the segmented control to its intrinsic size so the tabs never stretch with the
        // window or compress — a stable, fixed-size chrome control (layoutPriority is now moot).
        .fixedSize()
        .accessibilityLabel("Tab Navigation")
        .accessibilityValue(selectedTab.rawValue)
    }
}
