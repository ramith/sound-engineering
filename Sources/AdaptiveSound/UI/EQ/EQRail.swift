import DesignTokenKit
import SwiftUI

// MARK: - EQ rail (Sprint EQ, EQ3 — V1b's left column)

/// The EQ screen's left column, the Library rail's width: the Equalizer card (On/Off, Presets, My
/// Presets) and, below it, the Tone card — `EQRail(save:) { EQToneCard() }` (EQ3t), which stays whole
/// and pinned while the Equalizer card scrolls inside itself when the window is short. The glow shows
/// below both.
struct EQRail<ToneCard: View>: View {
    /// Opens the Save sheet (My Presets' "+").
    let save: () -> Void
    /// The Tone card, built by the caller (the memberwise init takes the builder).
    @ViewBuilder let toneCard: ToneCard

    var body: some View {
        VStack(spacing: CGFloat(EQScreenLayout.railCardGap)) {
            EQEqualizerCard(save: save)
            toneCard
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: DesignSystem.LayoutMetrics.sidebarIdeal)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
