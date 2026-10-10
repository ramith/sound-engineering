// STROKE — the graph drag (EQ3a; review F12): today's numbers kept (the pointer's band at the
// pointer's level, held in ±12; the gap fill along a straight line; the bands one and two beyond the
// stroke following 0.75 and 0.25 of the way), now computed from the mouse-down curve every sample —
// so a held pointer never drifts its neighbours, and the same path always draws the same curve.

@testable import EQEditKit
import Testing

@Suite("EQStroke — the neighbours-follow drag, from the mouse-down curve")
struct EQStrokeTests {
    /// The points after `samples` (band, dB) from `start`.
    private static func draw(_ samples: [(Int, Float)], from start: EQCurve = .flat) -> [Float] {
        var stroke = EQStroke(start: start)
        var curve = start
        for (band, db) in samples {
            curve = stroke.curve(movingTo: band, db: db)
        }
        return curve.points
    }

    @Test("STROKE-01: one sample — the band at the pointer, ±1 at 0.75 and ±2 at 0.25 of the way")
    func singleSample() {
        #expect(EQFixture.close(Self.draw([(10, 6)]), EQFixture.points([8: 1.5, 9: 4.5, 10: 6, 11: 4.5, 12: 1.5])))
    }

    @Test("STROKE-02: holding still never compounds — 50 identical samples draw what one does")
    func noCompounding() {
        let once = Self.draw([(10, 6)])
        #expect(Self.draw(Array(repeating: (10, 6), count: 50)) == once)
    }

    @Test("STROKE-03: moving within a band, the neighbours follow from where they were at mouse-down")
    func neighboursFollowFromMouseDown() {
        // Up to +6 then down to −4: the shoulder is −3 / −1, not blended from the +4.5 / +1.5 on the way.
        #expect(EQFixture.close(Self.draw([(10, 6), (10, -4)]),
                                EQFixture.points([8: -1, 9: -3, 10: -4, 11: -3, 12: -1])))
    }

    @Test("STROKE-04: a fast sweep fills the skipped bands on a line; the stroke's two ends get the shoulders")
    func sweepFillsTheGap() {
        let swept = Self.draw([(5, 2), (9, 6)])
        #expect(EQFixture.close(swept, EQFixture.points([
            3: 0.5, 4: 1.5, // below the run, following band 5's +2
            5: 2, 6: 3, 7: 4, 8: 5, 9: 6, // the run: 6–8 on the line from +2 to +6
            10: 4.5, 11: 1.5, // above it, following band 9's +6
        ])))
        // Sweeping back over the run redraws it from the last sample, the same way.
        #expect(EQFixture.close(Self.draw([(5, 2), (9, 6), (7, 0)]), EQFixture.points([
            3: 0.5, 4: 1.5, 5: 2, 6: 3, 7: 0, 8: 3, 9: 6, 10: 4.5, 11: 1.5,
        ])))
    }

    @Test("STROKE-05: the ends of the grid, the ±12 hold, and a band past the grid")
    func limits() {
        #expect(EQFixture.close(Self.draw([(0, 6)]), EQFixture.points([0: 6, 1: 4.5, 2: 1.5])))
        #expect(EQFixture.close(Self.draw([(30, -6)]), EQFixture.points([30: -6, 29: -4.5, 28: -1.5])))
        #expect(EQFixture.close(Self.draw([(15, 20)]), EQFixture.points([13: 3, 14: 9, 15: 12, 16: 9, 17: 3])))
        #expect(EQFixture.close(Self.draw([(15, -30)]), EQFixture.points([13: -3, 14: -9, 15: -12, 16: -9, 17: -3])))
        #expect(Self.draw([(45, 6)]) == Self.draw([(30, 6)]))
        // A non-finite level is no sample: neither the first nor a later one moves anything.
        #expect(Self.draw([(10, .nan)]) == EQCurve.flat.points)
        #expect(Self.draw([(10, 6), (20, .infinity)]) == Self.draw([(10, 6)]))
    }

    @Test("STROKE-06: from a preset, neighbours follow from the preset's points")
    func fromAPreset() {
        let warm = EQBuiltInPreset.warm.points
        let drawn = Self.draw([(20, -6)], from: EQCurve(points: warm))
        var expected = warm
        expected[20] = -6
        for (offset, weight) in [(1, Float(0.75)), (2, Float(0.25))] {
            for band in [20 - offset, 20 + offset] {
                expected[band] = warm[band] + (-6 - warm[band]) * weight
            }
        }
        #expect(EQFixture.close(drawn, expected))
    }

    @Test("STROKE-07: under Tone, drawn points land exactly and untouched bands keep their base")
    func underTone() {
        let base = (0 ..< EQBands.count).map { Float($0 % 4) }
        let start = EQCurve(base: base, tone: EQFixture.tone([.mids: 6, .air: -4]))
        var stroke = EQStroke(start: start)
        let curve = stroke.curve(movingTo: 17, db: -2.5)
        #expect(abs(curve.points[17] + 2.5) <= EQFixture.tolerance)
        for band in 0 ..< EQBands.count where !(15 ... 19).contains(band) {
            #expect(curve.base[band] == start.base[band], "band \(band) moved")
        }
        #expect(curve.tone == start.tone)
    }
}
