import SwiftUI

// MARK: - Monitor Channel Row View

/// One full-width row in the Monitoring tab representing a single audio channel.
///
/// Each row shows the BEFORE spectrum (teal, left half) and the AFTER spectrum
/// (blue, right half), separated by a hairline. The layout mirrors the design in
/// `docs/sprints/05-sprint-5-monitoring-tab-design.md`.
///
/// - `channelIndex`:  0-based index into the engine's channel list.
/// - `channelLabel`:  Human-readable name, e.g. "L", "R", "C", "Ls".
/// - `beforeBands`:   Latest normalised band magnitudes from the pre-DSP tap.
/// - `afterBands`:    Latest normalised band magnitudes from the post-DSP tap.
/// - `isActive`:      `true` while the engine is playing; dims the spectra when `false`.
struct MonitorChannelRowView: View {
    let channelIndex: Int
    let channelLabel: String
    let beforeBands: [Float]
    let afterBands: [Float]
    let isActive: Bool

    // MARK: Constants

    private enum Layout {
        static let rowHeight: CGFloat = 72
        static let labelWidth: CGFloat = 28
        static let stageLabelHeight: CGFloat = 14
        static let hairlineWidth: CGFloat = 0.5
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = DesignSystem.Radius.container
        static let innerSpacing: CGFloat = DesignSystem.Spacing.xSmall
    }

    // Semantic colour tokens from the design spec:
    // teal (#1F9D8B family) = BEFORE, blue (#0A84FF) = AFTER.
    private let beforeColor = DesignSystem.Color.accent // teal
    private let afterColor = DesignSystem.Color.blue // blue

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            channelHeaderRow
            spectraRow
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(DesignSystem.Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .stroke(DesignSystem.Color.hairline, lineWidth: 0.5)
        )
        // VoiceOver: announce the row as a unit, naming channel + state.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRowLabel)
    }

    // MARK: Sub-views

    private var channelHeaderRow: some View {
        HStack(spacing: Layout.innerSpacing) {
            Text(channelLabel)
                .font(DesignSystem.Font.bodyMedium)
                .foregroundStyle(DesignSystem.Color.label)
                .frame(width: Layout.labelWidth, alignment: .leading)

            Spacer()

            HStack(spacing: Layout.innerSpacing) {
                stageTag(title: "BEFORE", color: beforeColor)
                stageTag(title: "AFTER", color: afterColor)
            }
        }
        .frame(height: Layout.stageLabelHeight)
        .padding(.bottom, Layout.innerSpacing)
    }

    private var spectraRow: some View {
        // Two equal halves separated by a hairline. `.frame(maxWidth: .infinity)` splits the width
        // 50/50 natively — no `GeometryReader` (which forced a layout pass per channel row just to
        // compute the halves by hand).
        HStack(spacing: 0) {
            SpectrumMiniView(bands: beforeBands, color: beforeColor, isActive: isActive)
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(DesignSystem.Color.hairline)
                .frame(width: Layout.hairlineWidth)

            SpectrumMiniView(bands: afterBands, color: afterColor, isActive: isActive)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.rowHeight)
    }

    // MARK: Helpers

    private func stageTag(title: String, color: Color) -> some View {
        Text(title)
            .font(DesignSystem.Font.micro)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    private var accessibilityRowLabel: String {
        let state = isActive ? "active" : "idle"
        return "Channel \(channelIndex + 1), \(channelLabel), before and after spectrum, \(state)"
    }
}
