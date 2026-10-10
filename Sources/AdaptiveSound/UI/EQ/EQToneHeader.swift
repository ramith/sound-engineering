import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - Tone header (EQ3t — the Tone card's one fixed line)

/// The Tone card's header: the fold chip — a chevron and the "TONE" caption, and while folded the
/// one-line summary ("all at 0 dB") — then Reset Tone, which is disabled while every region is at 0.
/// Folded, the reset keeps only its glyph, so the whole card is this one line.
///
/// Keyboard: both are Tab stops (the fold chip first) with the app's keyboard ring, pressed with
/// Return. VoiceOver: the chip is "Tone", valued "collapsed" / "expanded".
struct EQToneHeader: View {
    let isFolded: Bool
    let toggleFold: () -> Void

    @Environment(EQViewModel.self) private var eq

    var body: some View {
        HStack(spacing: CGFloat(EQScreenLayout.toneRowGap)) {
            Button(action: toggleFold) {
                HStack(spacing: CGFloat(EQScreenLayout.toneRowGap)) {
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .rotationEffect(.degrees(isFolded ? 0 : 90))
                    Text("Tone")
                        .fontWeight(.heavy)
                        .tracking(1)
                        .textCase(.uppercase)
                    if isFolded {
                        Text(EQToneText.summary(of: eq.current.resolvedCurve))
                            .font(DesignSystem.Font.caption)
                            .foregroundStyle(DesignSystem.Color.labelSecondary)
                            .lineLimit(1)
                    }
                }
                .font(DesignSystem.Font.micro)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .controlFocusRing(around: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
            .help(isFolded ? "Show the Tone sliders" : "Hide the Tone sliders")
            .accessibilityLabel("Tone")
            .accessibilityValue(isFolded ? "collapsed" : "expanded")

            Spacer(minLength: 0)

            Button("Reset Tone", systemImage: "arrow.counterclockwise", action: eq.resetTone)
                .labelStyle(EQToneResetLabelStyle(isIconOnly: isFolded))
                .font(DesignSystem.Font.caption)
                .foregroundStyle(eq.hasTone ? DesignSystem.Color.accentText : DesignSystem.Color.labelDisabled)
                .buttonStyle(.borderless)
                .controlFocusRing(around: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
                .disabled(!eq.hasTone)
                .help("Set every Tone region back to 0 dB")
        }
        // The rail's section-header inset (`NavSectionHeader`): the caption lines up with the
        // Equalizer card's "PRESETS" above it.
        .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
        .frame(height: CGFloat(EQScreenLayout.toneHeaderHeight))
    }
}
