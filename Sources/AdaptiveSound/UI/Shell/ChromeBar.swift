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
/// compresses) and sits on the trailing edge. The device pill (`OutputDevicePill`, shared with
/// Settings) hugs its content up to a width cap and truncates longer names, so an aggregate-device
/// name can't blow out the header.
struct ChromeBar: View {
    /// Binding to the tab selection owned by ContentView so the toolbar
    /// controls navigation without owning state it does not produce.
    @Binding var selectedTab: TabSelection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            AppLogoView()

            OutputDevicePill()

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
