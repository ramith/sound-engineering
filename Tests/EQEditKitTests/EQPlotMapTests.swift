// PLOT — the graph's coordinate map, moved into the kit (EQ3a): a log-frequency x over the ISO band
// table's own range, a linear ±20 dB y, and the inverse hit-test that picks a band by the SAME
// placement the dots are drawn at.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQPlotMap — the graph's axes and hit-test")
struct EQPlotMapTests {
    private let map = EQPlotMap(left: 50, right: 950, top: 20, bottom: 420)

    @Test("PLOT-01: the band table's ends sit exactly on the plot's edges")
    func frequencyAxisEnds() {
        #expect(map.x(forFreq: 20) == map.left)
        #expect(abs(map.x(forFreq: 20000) - map.right) < 1e-9)
        #expect(map.width == 900 && map.height == 400)
    }

    @Test("PLOT-02: the gain axis is linear over ±20 dB, and the pointer's y maps back within it")
    func gainAxis() {
        #expect(map.y(forGain: 20) == map.top)
        #expect(map.y(forGain: -20) == map.bottom)
        #expect(map.y(forGain: 0) == 220)
        for gain in stride(from: -20.0, through: 20, by: 2.5) {
            #expect(abs(map.gain(forY: map.y(forGain: gain)) - gain) < 1e-9)
        }
        #expect(map.gain(forY: -100) == 20)
        #expect(map.gain(forY: 900) == -20)
    }

    @Test("PLOT-03: every dot picks its own band; past either edge picks the end band")
    func nearestBand() {
        for (band, hz) in EQBands.nominalHz.enumerated() {
            #expect(map.nearestBand(toX: map.x(forFreq: hz)) == band, "\(hz) Hz")
        }
        #expect(map.nearestBand(toX: -500) == 0)
        #expect(map.nearestBand(toX: 5000) == EQBands.count - 1)
        #expect(EQPlotMap(left: 10, right: 10, top: 0, bottom: 10).nearestBand(toX: 10) == 0)
    }
}
