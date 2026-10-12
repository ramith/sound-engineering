import DesignTokenKit
import SwiftUI

// MARK: - Monitor Channel Row View

/// One audio channel in the Monitoring tab: what sits on its analyzer lens (S10.8 G1). The lens itself is
/// `MonitorLensStack`'s, drawn in one layer under every row so no lens's shadow falls on another's bars.
///
/// The channel's name sits in a fixed leading column; then the BEFORE half (neutral grey) and the AFTER
/// half (the analyzer's teal → lime), split by a hairline, each under its own tag (`MonitorStageView`) —
/// decision 4's colours (`MonitorColors`), told apart by position and label too. Every size comes from
/// `MonitorLayout`; the caller sets the height (the lenses share the tab's), and the halves fill it.
///
/// - `channelLabel`: The drawn name, e.g. "L", "C", "Ls" (`ChannelLabels`).
/// - `spokenName`:   What VoiceOver reads, e.g. "Left channel".
/// - `beforeBands`:  Latest normalised band magnitudes from the pre-DSP tap.
/// - `afterBands`:   Latest normalised band magnitudes from the post-DSP tap.
/// - `isActive`:     `true` while the engine is playing; dims the spectra when `false`.
struct MonitorChannelRowView: View {
    let channelLabel: String
    let spokenName: String
    let beforeBands: [Float]
    let afterBands: [Float]
    let isActive: Bool

    /// The rule between the halves: as thin as `Hairline`'s (which draws only horizontal rules).
    private static let dividerWidth: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Centred in the tag line, as the tags are, so the name reads on their line.
            Text(channelLabel)
                .font(DesignSystem.Font.bodyMedium)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(1)
                .frame(width: CGFloat(MonitorLayout.labelColumnWidth),
                       height: CGFloat(MonitorLayout.tagLineHeight), alignment: .leading)

            // Equally flexible, so the two halves split the width evenly, gap included.
            MonitorStageView(title: "Before", tagColor: MonitorColors.beforeText, bands: beforeBands,
                             barColors: .uniform(MonitorColors.beforeFill), isActive: isActive)
                .padding(.trailing, CGFloat(MonitorLayout.halfGap))

            Rectangle()
                .fill(DesignSystem.Color.hairline)
                .frame(width: Self.dividerWidth)

            MonitorStageView(title: "After", tagColor: MonitorColors.afterText, bands: afterBands,
                             barColors: .analyzerRamp, isActive: isActive)
                .padding(.leading, CGFloat(MonitorLayout.halfGap))
        }
        .padding(CGFloat(MonitorLayout.lensPadding))
        // VoiceOver: the row is one element, named for its channel; the bars are hidden (`SpectrumMiniView`).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenName), before and after spectrum")
        .accessibilityValue(isActive ? "active" : "idle")
    }
}
