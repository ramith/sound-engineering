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

    /// Whether `points` can be played: one finite value per band. Points from storage or from a My
    /// Preset are checked with this before they become a curve (`init(points:)` traps on a wrong
    /// count).
    public static func isWellFormed(_ points: [Float]) -> Bool {
        points.count == EQBands.count && points.allSatisfy(\.isFinite)
    }

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

    // MARK: - Editing (EQ3a)

    /// How far a point may sit from its preset's before the curve counts as edited (dB).
    private static let editedThresholdDb: Float = 0.05

    /// Sets the point at `band` so it PLAYS `db` (held in ±12): the base takes whatever the Tone
    /// layer doesn't (base = db − Tone offset), so the point lands on `db` within float error
    /// (≤ 1e-5 dB) whatever Tone is set. A band outside the grid, or a non-finite level, is ignored.
    public mutating func setPoint(_ band: Int, to db: Float) {
        guard base.indices.contains(band), db.isFinite else { return }
        let point = db.clamped(within: EQBands.pointLimitDb)
        base[band] = (point - toneOffset(atBand: band)).clamped(within: EQBands.baseLimitDb)
    }

    /// How far past ±12 dB base + Tone must ask before a point counts as held there: float sums of a
    /// point set exactly to ±12 under a Tone land within ~1e-6 of it, and must not read "limited".
    private static let limitToleranceDb: Float = 1e-4

    /// Whether the ceiling holds the point at `band` (ui-plan §4.3, "limited"): base + Tone asks for
    /// more than the ±12 dB a point may take, so moving Tone further doesn't move this point. A band
    /// off the grid is never limited.
    public func isLimited(atBand band: Int) -> Bool {
        guard base.indices.contains(band) else { return false }
        return abs(base[band] + toneOffset(atBand: band)) > EQBands.pointLimitDb + Self.limitToleranceDb
    }

    /// The same points with the Tone baked into the base and Tone at 0: what Save keeps.
    func baked() -> EQCurve {
        EQCurve(points: points)
    }

    /// Whether this curve plays something other than `presetPoints` — the "Edited" rule: any point
    /// more than 0.05 dB away, or any Tone set (a Tone move counts even where the ceiling holds the
    /// points still). Points of the wrong count never match.
    func isEdited(against presetPoints: [Float]) -> Bool {
        guard presetPoints.count == EQBands.count, tone.allSatisfy({ $0 == 0 }) else { return true }
        return zip(points, presetPoints).contains { abs($0 - $1) > Self.editedThresholdDb }
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
