// PLAYED — the played curve's value type (EQ3; engine-plan §8): the fixed response grid EQ1a's gate
// pins, and a read-back that is only ever whole and finite.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQPlayed — the played curve the graph draws")
struct EQPlayedTests {
    @Test("PLAYED-01: the grid is 256 log-spaced points, 20 Hz to 20 kHz, inside every design rate")
    func grid() throws {
        let grid = EQPlayed.frequencies
        #expect(grid.count == 256)
        #expect(try abs(#require(grid.first) - 20) < 1e-9)
        #expect(try abs(#require(grid.last) - 20000) < 1e-6)
        let ratios = zip(grid.dropFirst(), grid).map { $0 / $1 }
        #expect(ratios.allSatisfy { abs($0 - pow(1000, 1.0 / 255)) < 1e-9 })
        // Below the lowest design rate's Nyquist (44.1 kHz), as the C-ABI requires.
        #expect(grid.allSatisfy { $0 < 22050 })
    }

    @Test("PLAYED-02: a read-back is whole and finite, or there is none")
    func validation() {
        let centre = [Float](repeating: 1, count: EQBands.count)
        let response = [Float](repeating: 1, count: EQPlayed.frequencies.count)
        #expect(EQPlayed(centreDb: centre, responseDb: response) != nil)
        #expect(EQPlayed(centreDb: Array(centre.dropLast()), responseDb: response) == nil)
        #expect(EQPlayed(centreDb: centre, responseDb: response + [0]) == nil)
        var nan = response
        nan[100] = .nan
        #expect(EQPlayed(centreDb: centre, responseDb: nan) == nil)
    }
}
