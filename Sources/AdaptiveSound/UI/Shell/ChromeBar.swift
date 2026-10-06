import DesignTokenKit
import SwiftUI

/// The app-owned chrome header (the shell's top band).
///
/// Layout (left → right):
///   App logo squircle | Device dropdown pill | Spacer | Tab selector
///
/// `AppShell` owns the band height (`ShellMetrics.chromeHeight`), the window background,
/// and the bottom hairline, so this view sets none of those. Its leading edge shares the
/// content's left margin — with the native titlebar restored, the window buttons sit in their
/// own strip, so no traffic-light inset is needed.
///
/// The tab picker is `.fixedSize()` (locked to its intrinsic size — never stretches or
/// compresses) and sits on the trailing edge. The device pill hugs its content up to a width
/// cap and truncates longer names, so an aggregate-device name can't blow out the header.
struct ChromeBar: View {
    /// Binding to the tab selection owned by ContentView so the toolbar
    /// controls navigation without owning state it does not produce.
    @Binding var selectedTab: TabSelection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            AppLogoView()

            DevicePillView()

            Spacer(minLength: 8)

            // Realigned (`png/00`/`png/01`, founder round 1): the tab strip sits on the
            // chrome's RIGHT edge — logo + device pill left, spacer between.
            TabSelectorView(selectedTab: $selectedTab, reduceMotion: reduceMotion)
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

    /// The pill's maximum width. It HUGS its content up to this cap, then the device name
    /// truncates. (It was a fixed 302pt slot while the tab strip sat directly to its right, so
    /// a device change could not slide the tabs; the tabs moved to the chrome's right edge in
    /// S10.8 founder round 1, so only the pill's own trailing edge moves now.)
    private static let maxWidth: CGFloat = 302

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
            pillLabel
        }
        // The WHOLE pill is the menu's label (`pillMenuStyle`). Under the old borderless style
        // only the icon + name were, drawn by AppKit: the rate had to sit beside the menu to
        // update at all, which left the pill's trailing half unclickable, and AppKit's own bezel
        // insets truncated "MacBook Pro Speak…" with empty space right next to it (founder
        // screenshot, 2026-10-06).
        .pillMenuStyle()
        .accessibilityLabel("Audio output device")
        .accessibilityValue(deviceAccessibilityValue)
        .accessibilityHint("Click to choose from available audio output devices")
    }

    private var pillLabel: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.selectedDevice?.systemIcon ?? "speaker.wave.2")
                Text(viewModel.selectedDevice?.name ?? "No Device")
                    .lineLimit(1)
                    .truncationMode(.tail)
                // Realigned (png/01): an explicit dropdown chevron after the name.
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.asLabelTertiary)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.asLabel)

            // D5: the device's live sample rate, digits rolling (`numericText`) when it changes.
            // Present only while a rate is known — an idle pill is just the device, with no
            // blank reserved slot. While shown it keeps a FIXED slot, so a rate change
            // (44.1 → 176.4 kHz) rolls the digits without resizing the pill.
            if achievedRate > 0 {
                Text(SignalPathInfo.rateString(achievedRate))
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(Color.asLabelSecond)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    // The slot fits every rate at default size (SLOT-02); a 9-char hi-res rate
                    // ("176.4 kHz") at the clamped .xLarge max shrinks to fit rather than
                    // truncating away the "kHz" unit.
                    .minimumScaleFactor(0.7)
                    .frame(width: CGFloat(SlotWidths.chromeSampleRate), alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        // The 8a glass "small-control" fill (the .badge role — same white-8% recipe the
        // mock's device pill uses).
        .glassPanel(.badge, in: Capsule())
        .contentShape(Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: achievedRate)
    }

    private var deviceAccessibilityValue: String {
        let name = viewModel.selectedDevice?.displayName ?? "No device selected"
        guard achievedRate > 0 else { return name }
        return "\(name), \(SignalPathInfo.rateString(achievedRate).replacing(" kHz", with: " kilohertz"))"
    }
}

// MARK: - Tab Selector

/// The realigned capsule tab strip (S10.8 PR B, D9 reopened — founder 2026-07-19): a carved
/// dark track holding one teal-gradient capsule for the active tab; inactive tabs lighten on
/// hover. Replaces `.pickerStyle(.segmented)`. Each tab is a real `Button` (keyboard Tab +
/// Space/Return activation — the picker's arrow-key model is traded for standard button
/// focus, with the selection exposed via the `.isSelected` trait). Selection movement is
/// animated (`.snappy`), Reduce-Motion gated like the picker's old easing.
private struct TabSelectorView: View {
    @Binding var selectedTab: TabSelection
    let reduceMotion: Bool

    @State private var hoveredTab: TabSelection?
    /// Realigned: 28pt capsule in a 34pt track — scaled with Dynamic Type (the chrome band
    /// clamps at .xLarge) so the strip never clips its labels.
    @ScaledMetric(relativeTo: .callout)
    private var capsuleHeight = CGFloat(GlassDecor.tabCapsuleBaseHeight)

    var body: some View {
        HStack(spacing: CGFloat(GlassDecor.tabSpacing)) {
            ForEach(TabSelection.allCases, id: \.id) { tab in
                tabButton(tab)
            }
        }
        .padding(CGFloat(GlassDecor.tabTrackPadding))
        .background(TabTrackCapsule())
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: selectedTab)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab Navigation")
        .accessibilityValue(selectedTab.rawValue)
    }

    private func tabButton(_ tab: TabSelection) -> some View {
        let active = tab == selectedTab
        return Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.callout.weight(active ? .bold : .semibold))
                .foregroundStyle(active ? DesignSystem.Color.onAccent
                    : hoveredTab == tab ? DesignSystem.Color.label : DesignSystem.Color.labelSecondary)
                .lineLimit(1)
                .padding(.horizontal, 15)
                .frame(height: capsuleHeight)
                .background {
                    if active {
                        ActiveTabCapsule()
                    } else if hoveredTab == tab {
                        Capsule().fill(DesignSystem.Color.hoverWash)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hoveredTab = $0 ? tab : nil }
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
