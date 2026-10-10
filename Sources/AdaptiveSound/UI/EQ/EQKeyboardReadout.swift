import SwiftUI

// MARK: - EQ keyboard readout (Sprint EQ, EQ3 — ui-plan §5.3)

/// With the graph under the keyboard: the cursor point's readout ("1 kHz · set +4.0 dB · plays
/// +3.9 dB") on a badge, then its keys. The keys give way first where the lens is narrow.
struct EQKeyboardReadout: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(DesignSystem.Font.monoSmall.weight(.semibold))
                .foregroundStyle(DesignSystem.Color.label)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .glassPanel(.badge, in: Capsule())
                .fixedSize()
            ViewThatFits(in: .horizontal) {
                Text("← → band   ↑ ↓ ±0.5 dB   ⇧ ±3 dB")
                    .font(DesignSystem.Font.monoMicro)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .accessibilityHidden(true) // VoiceOver adjusts each point directly
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
}
