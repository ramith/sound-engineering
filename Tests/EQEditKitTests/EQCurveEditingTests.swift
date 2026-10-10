// EDIT — EQCurve's editing API (EQ3a): a point set lands exactly on what was asked (|Δ| ≤ 1e-5 dB)
// whatever Tone is set, the other bands keep their base untouched, Save's bake keeps the sound, and
// the "Edited" rule (0.05 dB; any Tone counts).

@testable import EQEditKit
import Testing

@Suite("EQCurve editing — setPoint, baked, the Edited rule")
struct EQCurveEditingTests {
    private static let tones: [[Float]] = [
        EQFixture.tone([:]),
        EQFixture.tone([.bass: 12, .body: -12, .mids: 7.5, .presence: -3.25, .air: 12]),
        EQFixture.tone([.bass: -12, .body: 12, .mids: -12, .presence: 12, .air: -12]),
        EQFixture.tone([.presence: 4.4]),
    ]

    @Test("EDIT-01: setPoint lands within 1e-5 dB at every band, under every Tone")
    func setPointLandsExactly() {
        for tone in Self.tones {
            for band in 0 ..< EQBands.count {
                for db: Float in [-12, -7.3, -0.05, 0, 0.1, 3.333, 11.99, 12] {
                    var curve = EQCurve(base: EQFixture.points([:]), tone: tone)
                    curve.setPoint(band, to: db)
                    #expect(abs(curve.points[band] - db) <= EQFixture.tolerance,
                            "band \(band), tone \(tone), asked \(db), got \(curve.points[band])")
                }
            }
        }
    }

    @Test("EDIT-02: setPoint holds the point in ±12 and moves only its own band's base")
    func setPointClampsAndIsLocal() {
        let tone = EQFixture.tone([.mids: 9])
        let start = EQCurve(base: (0 ..< EQBands.count).map { Float($0) - 15 }, tone: tone)
        var curve = start
        curve.setPoint(17, to: 30)
        #expect(abs(curve.points[17] - 12) <= EQFixture.tolerance)
        curve.setPoint(3, to: -30)
        #expect(abs(curve.points[3] + 12) <= EQFixture.tolerance)
        for band in 0 ..< EQBands.count where band != 17 && band != 3 {
            #expect(curve.base[band] == start.base[band], "band \(band) moved")
        }
        #expect(curve.tone == tone)
    }

    @Test("EDIT-03: the base takes what Tone doesn't — a point under +12 Bass can go below the floor")
    func baseTakesTheRest() {
        var curve = EQCurve(base: EQFixture.points([:]), tone: EQFixture.tone([.bass: 12]))
        curve.setPoint(0, to: -12) // band 0 is all Bass: base = −12 − 12 = −24
        #expect(curve.base[0] == -24)
        #expect(abs(curve.points[0] + 12) <= EQFixture.tolerance)
    }

    @Test("EDIT-04: a band outside the grid, or a non-finite level, is ignored")
    func outOfGridIsIgnored() {
        var curve = EQCurve.flat
        curve.setPoint(-1, to: 6)
        curve.setPoint(EQBands.count, to: 6)
        curve.setPoint(4, to: .nan)
        curve.setPoint(5, to: .infinity)
        #expect(curve == .flat)
    }

    @Test("EDIT-05: baked keeps every point and moves the Tone into the base")
    func bakedKeepsTheSound() {
        let curve = EQCurve(base: (0 ..< EQBands.count).map { Float($0 % 9) - 4 },
                            tone: EQFixture.tone([.bass: 5, .air: -7.5, .mids: 2]))
        let baked = curve.baked()
        #expect(EQFixture.close(baked.points, curve.points))
        #expect(baked.tone == EQFixture.tone([:]))
    }

    @Test("EDIT-06: the Edited rule — more than 0.05 dB from the preset, or any Tone")
    func editedRule() {
        let warm = EQBuiltInPreset.warm.points
        #expect(!EQCurve(points: warm).isEdited(against: warm))
        var nudged = warm
        nudged[20] += 0.04
        #expect(!EQCurve(points: nudged).isEdited(against: warm), "0.04 dB is within the rule")
        nudged[20] += 0.03
        #expect(EQCurve(points: nudged).isEdited(against: warm), "0.07 dB is an edit")
        // A Tone set counts even where the ceiling holds the points still (all already at +12).
        let ceiling = [Float](repeating: 12, count: EQBands.count)
        let toned = EQCurve(base: ceiling, tone: EQFixture.tone([.air: 3]))
        #expect(toned.points == ceiling)
        #expect(toned.isEdited(against: ceiling))
        // Points of the wrong count never match.
        #expect(EQCurve.flat.isEdited(against: [0, 0, 0]))
    }
}
