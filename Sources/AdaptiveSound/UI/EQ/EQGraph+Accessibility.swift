import EQEditKit
import SettingsKit
import SwiftUI

// MARK: - EQ graph: VoiceOver (ui-plan §5.4)

extension EQGraph {
    /// A VoiceOver point's side: a square centred on the drawn point, the size of a comfortable target.
    static let accessiblePointSide: CGFloat = 24
}

extension View {
    /// The EQ graph as VoiceOver hears it: one container, "Equalizer graph", whose value says what plays
    /// ("Warm, edited", "Off", "Comparing", "Pure Mode"), holding 31 adjustable points — "1 kilohertz",
    /// "plus 4 decibels" — that step ±0.5 dB, add "plays …" only where the played level differs by
    /// 0.2 dB or more and "limited" where the ceiling holds them, and offer "Reset band". The points are
    /// synthetic children: never drawn, never hit-tested, so they can't intercept the drag. Each sits
    /// where its point is drawn (`map`), so VoiceOver's cursor rings the point itself.
    /// While Pure plays the points are inert, like the graph (`availability`).
    func graphAccessibility(eq: EQViewModel, reading: EQGraphReading, map: EQPlotMap,
                            availability: DSPRowAvailability) -> some View {
        accessibilityElement()
            .accessibilityLabel("Equalizer graph")
            .accessibilityValue(EQReadout.spokenState(of: eq))
            .accessibilityHint("Swipe up or down on a point to adjust it, or drag the curve with a pointer.")
            .accessibilityChildren {
                ZStack(alignment: .topLeading) {
                    ForEach(reading.points.indices, id: \.self) { band in
                        EQGraphAccessiblePoint(eq: eq, reading: reading, band: band, availability: availability)
                            .frame(width: EQGraph.accessiblePointSide, height: EQGraph.accessiblePointSide)
                            .position(x: map.x(forFreq: EQBands.nominalHz[band]),
                                      y: map.y(forGain: Double(reading.points[band])))
                    }
                }
            }
    }
}
