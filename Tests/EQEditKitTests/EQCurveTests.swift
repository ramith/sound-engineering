// CURVE — the base/tone/points maths (the Sprint EQ contract): points = clamp(base + Σ tone·w,
// ±12), base held in ±24, tone in ±12, and a curve stores base + tone, never points.
// Float landings are checked to |Δ| ≤ 1e-5 dB (breaker m9: float sums are not exact).

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQCurve — base + tone → points")
struct EQCurveTests {
    private static let tolerance: Float = 1e-5
    private static let noTone = [Float](repeating: 0, count: EQToneRegion.allCases.count)

    private static func tone(_ values: [EQToneRegion: Float]) -> [Float] {
        EQToneRegion.allCases.map { values[$0] ?? 0 }
    }

    private static func base(_ value: Float) -> [Float] {
        [Float](repeating: value, count: EQBands.count)
    }

    @Test("CURVE-01: flat plays 0 dB at every band")
    func flatIsZero() {
        #expect(EQCurve.flat.points == Self.base(0))
    }

    @Test("CURVE-02: a curve made from points plays exactly those points, with no Tone")
    func pointsRoundTrip() {
        let points = (0 ..< EQBands.count).map { Float($0 % 7) * 1.5 - 4.5 } // −4.5 … +4.5
        let curve = EQCurve(points: points)
        #expect(curve.points == points)
        #expect(curve.tone == Self.noTone)
        #expect(EQCurve(points: EQBuiltInPreset.warm.points).points == EQBuiltInPreset.warm.points)
    }

    @Test("CURVE-03: a point is held in ±12 dB")
    func pointsClamp() {
        let wild: [Float] = (0 ..< EQBands.count).map { $0.isMultiple(of: 2) ? 30 : -30 }
        let held = EQCurve(points: wild).points
        #expect(held.allSatisfy { abs($0) == 12 })
        #expect(held[0] == 12 && held[1] == -12)
    }

    @Test("CURVE-04: each layer is held in its own limit — base ±24, tone ±12")
    func layerClamps() {
        let curve = EQCurve(base: Self.base(30), tone: Self.tone([.bass: -20, .air: 20]))
        #expect(curve.base == Self.base(24))
        #expect(curve.tone == Self.tone([.bass: -12, .air: 12]))
    }

    @Test("CURVE-05: points = base + Σ tone·weight, band by band")
    func toneMath() {
        let base = (0 ..< EQBands.count).map { Float($0 % 5) - 2 } // −2 … +2
        let tone = Self.tone([.bass: 6, .body: -3, .presence: 4, .air: 6])
        let curve = EQCurve(base: base, tone: tone)
        for band in 0 ..< EQBands.count {
            let offset = EQToneRegion.allCases.reduce(0.0) { sum, region in
                sum + Double(tone[region.rawValue]) * region.weight(atHz: EQBands.centreHz[band])
            }
            let expected = Float(Double(base[band]) + offset)
            #expect(abs(curve.points[band] - expected) <= Self.tolerance, "band \(band)")
        }
    }

    @Test("CURVE-06: every region at +x lifts every point by x (the Baxandall level-at-mid property)")
    func allRegionsAreABroadbandGain() {
        for gain: Float in [12, 5.5, -7.5] {
            let tone = [Float](repeating: gain, count: EQToneRegion.allCases.count)
            let points = EQCurve(base: Self.base(0), tone: tone).points
            #expect(points.allSatisfy { abs($0 - gain) <= Self.tolerance }, "all regions at \(gain)")
        }
    }

    @Test("CURVE-07: the ±12 clamp comes after Tone is added, so base beyond ±12 still counts")
    func clampAfterSumming() {
        // Band 0 (20 Hz) is all Bass. A +18 base under a −12 Bass plays +6, not clamp(18) − 12 = 0.
        let lifted = EQCurve(base: [18] + Self.base(0).dropFirst(), tone: Self.tone([.bass: -12]))
        #expect(abs(lifted.points[0] - 6) <= Self.tolerance)
        // A Tone push past the ceiling is held at +12 and leaves the base untouched.
        let pushed = EQCurve(base: Self.base(10), tone: Self.tone([.bass: 12]))
        #expect(pushed.points[0] == 12)
        #expect(pushed.base[0] == 10)
    }

    @Test("CURVE-08: a curve encodes base + tone (never points) and decodes back equal")
    func codableRoundTrip() throws {
        let curve = EQCurve(base: (0 ..< EQBands.count).map { Float($0) - 15 }, tone: Self.tone([.mids: 3.5]))
        let data = try JSONEncoder().encode(curve)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys) == ["base", "tone"])
        #expect(try JSONDecoder().decode(EQCurve.self, from: data) == curve)
    }

    @Test("CURVE-09: decoding rejects the wrong counts or a non-finite value, and holds the limits")
    func decodingChecksTheInvariant() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        func decode(base: String, tone: String) throws -> EQCurve {
            try decoder.decode(EQCurve.self, from: Data(#"{"base":\#(base),"tone":\#(tone)}"#.utf8))
        }
        let base31 = "[" + Array(repeating: "0", count: EQBands.count).joined(separator: ",") + "]"
        #expect(throws: DecodingError.self) { try decode(base: "[0,0,0]", tone: "[0,0,0,0,0]") }
        #expect(throws: DecodingError.self) { try decode(base: base31, tone: "[0,0,0,0]") }
        #expect(throws: DecodingError.self) { try decode(base: base31, tone: #"[0,"nan",0,0,0]"#) }
        #expect(throws: DecodingError.self) {
            try decode(base: base31.replacingOccurrences(of: "[0,", with: #"["inf","#), tone: "[0,0,0,0,0]")
        }
        let held = try decode(base: base31.replacingOccurrences(of: "[0,", with: "[40,"), tone: "[0,-30,0,0,0]")
        #expect(held.base[0] == 24)
        #expect(held.tone == Self.tone([.body: -12]))
    }
}
