import EQEditKit
import SwiftUI

// MARK: - EQ graph: one VoiceOver point (ui-plan §5.4)

/// One band as VoiceOver hears it: "1 kilohertz", "plus 4 decibels" (adding "plays …" and "limited"
/// where they apply), adjustable by ±0.5 dB, with a "Reset band" action. Never drawn: the graph places
/// it over its point (`graphAccessibility`).
struct EQGraphAccessiblePoint: View {
    let eq: EQViewModel
    let reading: EQGraphReading
    let band: Int

    var body: some View {
        Rectangle()
            .accessibilityLabel(EQReadout.spokenFrequency(EQBands.nominalHz[band]))
            .accessibilityValue(EQReadout.spokenPoint(set: reading.points[band], plays: reading.played?.centreDb[band],
                                                      limited: reading.limited[band]))
            .accessibilityAdjustableAction(adjust)
            .accessibilityAction(named: "Reset band", reset)
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        eq.nudge(band: band, by: direction == .increment ? EQGraph.stepDb : -EQGraph.stepDb)
    }

    private func reset() {
        eq.resetBand(band)
    }
}
