// EQStroke — one drag on the EQ graph (Sprint EQ, EQ3a; review F12). Today's neighbours-follow
// drag, moved out of `FrequencyResponseCanvas` with its numbers kept: the pointer's band takes the
// pointer's level (held in ±12), a fast sweep fills the bands it skipped along a straight line,
// and the bands one and two beyond the stroke follow it 0.75 and 0.25 of the way.
//
// What changed is where the neighbours follow FROM. The canvas blended each neighbour from its
// CURRENT value on every pointer sample, so the shoulder compounded: a pointer held for a few
// samples let the neighbours catch it up, and the 0.75 / 0.25 shoulder became a plateau by an
// amount that depended on the event rate. A stroke now computes every sample from the curve at
// mouse-down: a band the pointer has set keeps the level it set, and the neighbours follow from
// where they were at mouse-down. The same pointer path always draws the same curve, and Esc
// restores that snapshot exactly.
//
// The stroke works in points (what is drawn): `EQCurve.setPoint` lands each one exactly under any
// Tone, and a band the stroke never moves keeps its base untouched.

public struct EQStroke: Sendable {
    /// How the bands beyond each end of the stroke follow it: (distance in bands, share of the way).
    private static let shoulder: [(offset: Int, weight: Float)] = [(1, 0.75), (2, 0.25)]

    /// The curve at mouse-down, and its points: every sample starts from these.
    private let start: EQCurve
    private let startPoints: [Float]

    /// The level the pointer has set at each band it has reached, directly or by the gap fill. The
    /// gap fill joins consecutive samples, so these bands are always one contiguous run.
    private var drawn: [Int: Float] = [:]

    /// The previous sample's band, where a gap fill starts.
    private var lastBand: Int?

    /// A stroke starting from `start`, the curve at mouse-down.
    public init(start: EQCurve) {
        self.start = start
        startPoints = start.points
    }

    /// The curve once the pointer is at `band` (held to the grid) and `db` (held in ±12). A
    /// non-finite level is no sample: the curve stays as it was.
    public mutating func curve(movingTo band: Int, db: Float) -> EQCurve {
        guard db.isFinite else { return shaped() }
        let band = min(max(band, 0), EQBands.count - 1)
        let level = db.clamped(within: EQBands.pointLimitDb)
        if let lastBand, let from = drawn[lastBand], abs(band - lastBand) > 1 {
            fillGap(from: lastBand, level: from, to: band, level: level)
        }
        drawn[band] = level
        lastBand = band
        return shaped()
    }

    /// A fast sweep skips the bands between two samples: they take the straight line between the
    /// two levels.
    private mutating func fillGap(from fromBand: Int, level fromLevel: Float, to toBand: Int, level toLevel: Float) {
        let steps = abs(toBand - fromBand)
        let direction = toBand > fromBand ? 1 : -1
        for step in 1 ..< steps {
            let progress = Float(step) / Float(steps)
            drawn[fromBand + step * direction] = fromLevel + (toLevel - fromLevel) * progress
        }
    }

    /// The mouse-down curve with the drawn levels set, and the shoulder beyond each end of the run.
    private func shaped() -> EQCurve {
        var target = startPoints
        for (band, level) in drawn {
            target[band] = level
        }
        if let low = drawn.keys.min(), let high = drawn.keys.max() {
            for (offset, weight) in Self.shoulder {
                follow(&target, band: low - offset, toward: target[low], weight: weight)
                follow(&target, band: high + offset, toward: target[high], weight: weight)
            }
        }
        var curve = start
        for band in target.indices where target[band] != startPoints[band] {
            curve.setPoint(band, to: target[band])
        }
        return curve
    }

    /// Moves `band` (if on the grid) `weight` of the way from its mouse-down level toward `level`.
    private func follow(_ target: inout [Float], band: Int, toward level: Float, weight: Float) {
        guard target.indices.contains(band) else { return }
        let from = startPoints[band]
        target[band] = from + (level - from) * weight
    }
}
