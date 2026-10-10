import SwiftUI

// MARK: - EQ graph legend (Sprint EQ, EQ3)

/// "— plays  ● your setting  · drag a point, its neighbours follow smoothly": the line is the curve
/// the EQ plays, the dots are what you set. The hint gives way first where the lens is narrow, and
/// hides during a drag (the readout is over the point then).
struct EQGraphLegend: View {
    let showsHint: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Capsule()
                    .fill(DesignSystem.Color.accentFill)
                    .frame(width: 14, height: 2.5)
                Text("plays")
                Circle()
                    .fill(DesignSystem.Color.accentFill)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 6)
                Text("your setting")
            }
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The line is what plays; the dots are your setting")
            if showsHint {
                ViewThatFits(in: .horizontal) {
                    Text("·  drag a point, its neighbours follow smoothly")
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                    Color.clear.frame(width: 0, height: 0)
                }
            }
        }
    }
}
