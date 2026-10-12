import DesignTokenKit
import SwiftUI

// MARK: - Monitor Stage View

/// One half of a channel's lens (S10.8 G1): its stage's tag — BEFORE or AFTER — over that stage's bars,
/// left-aligned with them. Each tag sits over its own half, so position and label tell the two stages
/// apart without colour (plan §J — the founder's grayscale check); the colours are decision 4's
/// (`MonitorColors`).
struct MonitorStageView: View {
    /// The tag, e.g. "Before" (drawn uppercase).
    let title: String
    /// The tag's colour: its side's TEXT colour, not its bars' fill (R4-MON-03).
    let tagColor: Color
    let bands: [Float]
    let barColors: SpectrumMiniView.BarColors
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(MonitorLayout.tagGap)) {
            Text(title)
                .font(DesignSystem.Font.micro)
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(tagColor)
                .lineLimit(1)
                .frame(height: CGFloat(MonitorLayout.tagLineHeight))

            SpectrumMiniView(bands: bands, barColors: barColors, isActive: isActive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
