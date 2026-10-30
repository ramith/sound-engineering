import EQEditKit
import SettingsKit
import SwiftUI

// MARK: - EQ graph: one VoiceOver point (ui-plan §5.4)

/// One band as VoiceOver hears it: "1 kilohertz", "plus 4 decibels" (adding "plays …" and "limited"
/// where they apply), adjustable by ±0.5 dB, with a "Reset band" action. Never drawn: the graph places
/// it over its point (`graphAccessibility`). Inert while Pure plays, like the graph: dimmed, "Off in
/// bit-perfect mode", and its actions do nothing.
struct EQGraphAccessiblePoint: View {
    let eq: EQViewModel
    let reading: EQGraphReading
    let band: Int
    let availability: DSPRowAvailability

    var body: some View {
        Rectangle()
            .accessibilityLabel(EQReadout.spokenFrequency(EQBands.nominalHz[band]))
            .accessibilityValue(EQReadout.spokenPoint(set: reading.points[band], plays: reading.played?.centreDb[band],
                                                      limited: reading.limited[band]))
            .accessibilityAdjustableAction(adjust)
            .accessibilityAction(named: "Reset band", reset)
            .bitPerfectGate(.equalizer, availability)
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard availability.isLive else { return }
        eq.nudge(band: band, by: direction == .increment ? EQGraph.stepDb : -EQGraph.stepDb)
    }

    private func reset() {
        guard availability.isLive else { return }
        eq.resetBand(band)
    }
}
