import EQEditKit
import Foundation

// MARK: - EQ graph reading (Sprint EQ, EQ3; review fix round)

/// What one `EQGraph.body` reads from the view model, once: the points, the played curve, and which
/// points the ceiling holds ("limited"). The painter, the readouts and the 31 VoiceOver points all take
/// it as a value, so the curve is resolved once per redraw, not once per point.
struct EQGraphReading {
    let points: [Float]
    let played: EQPlayed?
    /// Per band: the ceiling holds the point (base + Tone asks past ±12 dB).
    let limited: [Bool]

    @MainActor
    init(_ eq: EQViewModel) {
        let curve = eq.current.resolvedCurve
        points = curve.points
        played = eq.played
        limited = points.indices.map(curve.isLimited(atBand:))
    }

    /// The point readout for `band` (the drag tag and the keyboard strip): "1 kHz · set +4.0 dB · plays
    /// +3.9 dB", ending "· limited" while the ceiling holds it.
    func tag(band: Int) -> String {
        EQReadout.point(band: band, set: points[band], plays: played?.centreDb[band], limited: limited[band])
    }
}
