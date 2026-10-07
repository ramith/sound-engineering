import DesignTokenKit
import SwiftUI

// MARK: - Format Badge

/// Small rounded badge showing a track's file format (e.g. "FLAC", "MP3").
/// Shared by the playlist row and the track-info card so the styling lives in one place.
struct FormatBadgeView: View {
    let format: String
    var isSelected: Bool = false

    /// 8a metric (18pt chip) — @ScaledMetric so larger text sizes grow the chip instead of
    /// clipping (break-it finding 3: the fixed frame regressed the old padding-based chip).
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = 18

    var body: some View {
        // 8a metrics (deviations §3): 18pt capsule-ish chip, radius = height/2.
        // Selected/current tint (S10.8 PR D, realigned `png/04`): the audited chip pair —
        // accentText on the accent-derived controlActiveFill (R4-CHIP-01).
        // Light edges the chip (S10.8 B3): neither fill separates from its card or row on its own
        // (white ~1.07:1, the teal ~1.10:1) — R4-CHIP-03.
        let shape = RoundedRectangle(cornerRadius: chipHeight / 2, style: .continuous)
        Text(format)
            .font(DesignSystem.Font.micro)
            .padding(.horizontal, 6)
            .frame(height: chipHeight)
            .background(isSelected ? DesignSystem.Color.controlActiveFill : Color.asCard)
            .foregroundStyle(isSelected ? DesignSystem.Color.accentText : Color.asLabelSecond)
            .lightEdge(GlassDecor.controlEdgeLight, in: shape)
            .clipShape(shape) // after the edge: the inset stroke's flatter ends never poke out
    }
}
