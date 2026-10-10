// EQPlotMap — the EQ graph's coordinate map (Sprint EQ, EQ3a: moved into the kit from
// `FrequencyResponseCanvas+Drawing`, numbers unchanged). The single source of truth for converting
// between screen points and the plot's two axes — a LOGARITHMIC frequency x-axis and a LINEAR
// gain y-axis — plus the inverse hit-test (`nearestBand(toX:)`). Drawing and drag / keyboard
// hit-testing both go through this one map, so a point is placed and picked by identical math.
//
// The frequency axis is DERIVED from `EQBands.nominalHz` (not hard-coded 20 / 20000), and all
// frequency work is in log space, so there is no `pow(10,·)` → `log10(·)` round-trip to nudge the
// 20 kHz / 20 Hz endpoint a hair out of range. The gain axis shows ±`gainSpan` dB; the tighter
// ±12 dB a point may take is the editor's clamp, not a plot concern.

import Foundation

public struct EQPlotMap: Sendable {
    public let left: CGFloat
    public let right: CGFloat
    public let top: CGFloat
    public let bottom: CGFloat

    public init(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public var width: CGFloat {
        right - left
    }

    public var height: CGFloat {
        bottom - top
    }

    /// Visual half-span of the gain axis: the ±12 dB a point may take plus a 3 dB margin (ui-plan §5.6),
    /// where a stroke past the ceiling shows the level it asked for. (EQ3; was ±20.)
    static let gainSpan: Double = 15

    /// Band centre frequencies in log10 space, computed once. The axis bounds are its endpoints, so
    /// the range tracks the band table automatically.
    static let isoLogFreqs: [Double] = EQBands.nominalHz.map { log10($0) }
    static let logFreqMin: Double = isoLogFreqs.first ?? log10(20)
    static let logFreqMax: Double = isoLogFreqs.last ?? log10(20000)

    // MARK: Axis transforms

    public func x(forLogFreq logFreq: Double) -> CGFloat {
        let span = Self.logFreqMax - Self.logFreqMin
        let ratio = span > 0 ? (logFreq - Self.logFreqMin) / span : 0
        return left + CGFloat(ratio) * width
    }

    public func x(forFreq freq: Double) -> CGFloat {
        x(forLogFreq: log10(freq))
    }

    public func y(forGain gain: Double) -> CGFloat {
        let ratio = (gain + Self.gainSpan) / (2 * Self.gainSpan)
        return bottom - CGFloat(ratio) * height
    }

    /// Screen y → gain in the VISUAL span [−`gainSpan`, +`gainSpan`]. The editor clamps to ±12.
    public func gain(forY y: CGFloat) -> Double {
        guard height > 0 else { return 0 }
        let ratio = min(max(Double((bottom - y) / height), 0), 1)
        return ratio * (2 * Self.gainSpan) - Self.gainSpan
    }

    // MARK: Inverse hit-test

    /// The band whose plotted position is nearest screen `x` — the drag / keyboard pick. Because it
    /// uses the SAME log-frequency placement as the dots, clicking on or beside a dot always selects
    /// that dot's band, and an `x` past either edge resolves to the nearest end band.
    public func nearestBand(toX x: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let span = Self.logFreqMax - Self.logFreqMin
        let logFreq = Self.logFreqMin + Double((x - left) / width) * span
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, bandLogFreq) in Self.isoLogFreqs.enumerated() {
            let distance = abs(bandLogFreq - logFreq)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}
