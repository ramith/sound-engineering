import EQEditKit
import SwiftUI

// MARK: - EQ graph: VoiceOver (ui-plan §5.4)

extension View {
    /// The EQ graph as VoiceOver hears it: one container, "Equalizer graph", whose value says what plays
    /// ("Warm, edited", "Off", "Comparing", "Pure Mode"), holding 31 adjustable points — "1 kilohertz",
    /// "plus 4 decibels" — that step ±0.5 dB, add "plays …" only where the played level differs by
    /// 0.2 dB or more and "limited" where the ceiling holds them, and offer "Reset band". The points are
    /// synthetic children: never drawn, never hit-tested, so they can't intercept the drag.
    func graphAccessibility(eq: EQViewModel, points: [Float], played: EQPlayed?) -> some View {
        accessibilityElement()
            .accessibilityLabel("Equalizer graph")
            .accessibilityValue(EQReadout.spokenState(of: eq))
            .accessibilityHint("Swipe up or down on a point to adjust it, or drag the curve with a pointer.")
            .accessibilityChildren {
                ForEach(points.indices, id: \.self) { band in
                    Rectangle()
                        .accessibilityLabel(EQReadout.spokenFrequency(EQBands.nominalHz[band]))
                        .accessibilityValue(EQReadout.spokenPoint(
                            set: points[band], plays: played?.centreDb[band],
                            limited: eq.current.resolvedCurve.isLimited(atBand: band)
                        ))
                        .accessibilityAdjustableAction { direction in
                            let step = direction == .increment ? EQGraph.stepDb : -EQGraph.stepDb
                            eq.nudge(band: band, by: step)
                        }
                        .accessibilityAction(named: "Reset band") { eq.resetBand(band) }
                }
            }
    }
}
