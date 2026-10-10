import SwiftUI

// MARK: - EQ state chip (Sprint EQ, EQ3 — "Edited" / "Off" beside the preset name)

/// The small capsule beside the graph card's preset name: "Edited" (teal, on the chip's on fill) while
/// the curve differs from its preset, "Off" (secondary, on the badge wash) while the EQ is off.
/// Audited R4-CHIP-EQ.
struct EQStateChip: View {
    enum Kind {
        case edited
        case off
    }

    let kind: Kind

    var body: some View {
        Text(kind == .edited ? "Edited" : "Off")
            .font(DesignSystem.Font.caption.weight(.semibold))
            .foregroundStyle(kind == .edited ? DesignSystem.Color.accentText : DesignSystem.Color.labelSecondary)
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .background(kind == .edited ? DesignSystem.Color.controlActiveFill : DesignSystem.Color.hoverWash,
                        in: Capsule())
            .fixedSize()
    }
}
