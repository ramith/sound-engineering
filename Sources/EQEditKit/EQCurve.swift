// EQCurve — one EQ curve as the user built it (Sprint EQ, EQ0; the contract's names, review
// F2): `base`, the user's own layer, plus `tone`, the five Tone macros. What plays is derived,
// never stored: `points` = clamp(base + Σ tone·weight, ±12), the values drawn AND sent to the
// engine. A curve therefore encodes base + tone only, and a stored curve always replays
// through today's Tone weights and limits.

import Foundation

public struct EQCurve: Equatable, Codable, Sendable {
    /// The user's layer, one value per band, held in ±`EQBands.baseLimitDb`.
    private(set) var base: [Float]

    /// One value per `EQToneRegion` (indexed by its raw value), held in ±`EQBands.toneLimitDb`.
    private(set) var tone: [Float]

    /// The flat curve: every point at 0 dB. What the engine plays when the EQ is off.
    public static let flat = EQCurve(points: [Float](repeating: 0, count: EQBands.count))

    /// The curve that plays exactly `points` (each held in ±`EQBands.pointLimitDb`), with no
    /// Tone. `points` must hold one value per band.
    public init(points: [Float]) {
        self.init(base: points.map { $0.clamped(within: EQBands.pointLimitDb) },
                  tone: [Float](repeating: 0, count: EQToneRegion.allCases.count))
    }

    /// A curve from its two layers, each held in its own limit. The counts are the type's
    /// invariant (one base value per band, one tone value per region).
    init(base: [Float], tone: [Float]) {
        precondition(base.count == EQBands.count, "EQCurve.base needs one value per band")
        precondition(tone.count == EQToneRegion.allCases.count, "EQCurve.tone needs one value per region")
        self.base = base.map { $0.clamped(within: EQBands.baseLimitDb) }
        self.tone = tone.map { $0.clamped(within: EQBands.toneLimitDb) }
    }

    /// The 31 values drawn and sent: base + the Tone offset, held in ±`EQBands.pointLimitDb`.
    public var points: [Float] {
        (0 ..< EQBands.count).map { band in
            (base[band] + toneOffset(atBand: band)).clamped(within: EQBands.pointLimitDb)
        }
    }

    /// What the Tone layer adds at `band`: Σ over the regions of tone · weight.
    func toneOffset(atBand band: Int) -> Float {
        zip(tone, EQToneRegion.bandWeights).reduce(0) { offset, layer in
            let (value, weights) = layer
            return offset + value * weights[band]
        }
    }

    // MARK: - Codable (base + tone; the invariant is checked, never trusted)

    private enum CodingKeys: String, CodingKey {
        case base, tone
    }

    /// Decodes the two layers, rejecting a stored curve with the wrong counts or a non-finite
    /// value (so a corrupt blob can never index out of range or play NaN); in-range values are
    /// held in their layer limits like any other curve.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = try container.decode([Float].self, forKey: .base)
        let tone = try container.decode([Float].self, forKey: .tone)
        guard base.count == EQBands.count, tone.count == EQToneRegion.allCases.count,
              (base + tone).allSatisfy(\.isFinite)
        else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "EQCurve needs \(EQBands.count) finite base values and "
                    + "\(EQToneRegion.allCases.count) finite tone values"
            ))
        }
        self.init(base: base, tone: tone)
    }
}
