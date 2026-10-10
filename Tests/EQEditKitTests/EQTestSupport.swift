// Shared fixtures for the EQ3a kit tests: Tone vectors, curves from a band → dB map, the 1e-5 dB
// landing tolerance (breaker m9: float sums are not exact), and JSON helpers for the stored forms.

@testable import EQEditKit
import Foundation

enum EQFixture {
    /// How close a point must land on what was asked of it (dB).
    static let tolerance: Float = 1e-5

    /// A Tone vector, one value per region (unlisted regions at 0).
    static func tone(_ values: [EQToneRegion: Float]) -> [Float] {
        EQToneRegion.allCases.map { values[$0] ?? 0 }
    }

    /// 31 points: `values` at their bands, 0 elsewhere.
    static func points(_ values: [Int: Float]) -> [Float] {
        (0 ..< EQBands.count).map { values[$0] ?? 0 }
    }

    /// A curve whose points are exactly `values` (0 elsewhere), with no Tone.
    static func curve(_ values: [Int: Float]) -> EQCurve {
        EQCurve(points: points(values))
    }

    /// Whether two point vectors agree band by band within `tolerance`.
    static func close(_ lhs: [Float], _ rhs: [Float], within tolerance: Float = tolerance) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// `value` encoded with sorted keys, as a string (the stored form, byte-stable).
    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try String(bytes: encoder.encode(value), encoding: .utf8) ?? ""
    }

    /// A JSON array literal of `values`.
    static func jsonArray(_ values: [Float]) -> String {
        "[" + values.map { "\($0)" }.joined(separator: ",") + "]"
    }

    /// `json` decoded as `T`.
    static func decode<T: Decodable>(_: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
