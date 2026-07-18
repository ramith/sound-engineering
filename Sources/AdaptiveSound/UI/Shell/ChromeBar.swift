import DesignTokenKit
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
        // Fixed 60pt band (like the footer): clamp text scale so accessibility sizes don't
        // overflow the chrome (the device pill + segmented tabs grow with type). PR 6 — the
        // strict-gate clamp guard asserts this stays present.
        .dynamicTypeSize(.small ... .xLarge)
    }
}

// MARK: - App Logo

private struct AppLogoView: View {
    var body: some View {
        ZStack {
            // Radius 9 squircle + the waveform brand mark (deviations §1 — the 8a mark is
            // the 5-bar waveform, not a note glyph).
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient.asIconFill)
                .frame(width: 30, height: 30)

            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Color.onAccent)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Device Dropdown Pill

private struct DevicePillView: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The device's live output rate (0 when idle → the readout slot stays empty). Enhanced
    /// now publishes this too (PR 6), so it's populated on both paths while playing.
    private var achievedRate: Double {
        viewModel.signalPath.achievedSampleRate
    }

    var body: some View {
        // The rate readout lives OUTSIDE the Menu's label, beside it in the shared capsule:
        // macOS does NOT reliably re-render a Menu's custom label when observed data changes
        // (the founder's screenshots showed the rate stuck empty while the hero badge and
        // footer — plain views on the same property — updated live; it refreshed only on a
        // device switch, which rebuilds the menu). A sibling Text updates like any view.
        HStack(spacing: 8) {
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
                HStack(spacing: 6) {
                    Image(systemName: viewModel.selectedDevice?.systemIcon ?? "speaker.wave.2")
                    Text(viewModel.selectedDevice?.name ?? "No Device")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.asLabel)
            }
            .accessibilityLabel("Audio output device")
            .accessibilityValue(deviceAccessibilityValue)
            .accessibilityHint("Click to choose from available audio output devices")

            Spacer(minLength: 8)

            // D5: the device's live sample rate, digits rolling (`numericText`) when it
            // changes. Reserved fixed slot — empty until a rate is known, so the pill's
            // fixed width (and the tabs' x-origin) never move.
            Text(achievedRate > 0 ? SignalPathInfo.rateString(achievedRate) : "")
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(Color.asLabelSecond)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: achievedRate)
                .lineLimit(1)
                // The slot fits every rate at default size (SLOT-02); a 9-char hi-res rate
                // ("176.4 kHz") at the clamped .xLarge max shrinks to fit rather than
                // truncating away the "kHz" unit.
                .minimumScaleFactor(0.7)
                .frame(width: CGFloat(SlotWidths.chromeSampleRate), alignment: .trailing)
                .accessibilityHidden(true) // folded into the Menu's a11y value above
        }
        .padding(.horizontal, 12)
        // Fixed width (minWidth == maxWidth), not a range: the pill's width was tracking the
        // device NAME, which slid the tab control's left edge on every device change. Fixed →
        // tabs' x-origin is invariant (the founder's "fixed top-left"). Long names truncate
        // (the text compresses before the spacer's 8pt minimum or the rate slot give way).
        // 288 (was 252): the PR-6 rate slot squeezed the name area to ~140pt and truncated
        // common device names ("MacBook Pr…") — the deviations audit's fresh catch.
        .frame(minWidth: 288, maxWidth: 288, minHeight: 32, alignment: .leading)
        // The 8a glass "small-control" fill (the .badge role — same white-8% recipe the
        // mock's device pill uses), replacing the old flat card + hand-drawn hairline.
        .glassPanel(.badge, in: Capsule())
    }

    private var deviceAccessibilityValue: String {
        let name = viewModel.selectedDevice?.displayName ?? "No device selected"
        guard achievedRate > 0 else { return name }
        return "\(name), \(SignalPathInfo.rateString(achievedRate).replacing(" kHz", with: " kilohertz"))"
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
