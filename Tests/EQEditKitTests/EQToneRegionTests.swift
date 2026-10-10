// TONE — the five Tone regions' weights (decision 24; literature survey §6): a raised-cosine
// partition of unity on log₂ f with crossovers at 150 / 500 / 2 k / 6 kHz, one octave wide.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQToneRegion — Tone weights")
struct EQToneRegionTests {
    /// Every frequency the weights are checked at: the 31 exact band centres, the crossovers and
    /// the edges of their one-octave transitions, and a dense log sweep across the audio band.
    private static let probeHz: [Double] = EQBands.centreHz
        + [150, 500, 2000, 6000].flatMap { [$0 / 2.squareRoot(), $0, $0 * 2.squareRoot()] }
        + (0 ... 440).map { 10 * pow(2, Double($0) / 40) } // 10 Hz … 20.5 kHz, 1/40 octave

    @Test("TONE-01: the five weights sum to exactly 1 at every frequency (partition of unity)")
    func partitionOfUnity() {
        for hz in Self.probeHz {
            let sum = EQToneRegion.allCases.reduce(0) { $0 + $1.weight(atHz: hz) }
            #expect(abs(sum - 1) < 1e-12, "Σ weights at \(hz) Hz = \(sum)")
        }
    }

    @Test("TONE-02: the per-band table sums to 1 at every band (the Float copy the curve reads)")
    func bandTableSumsToOne() {
        #expect(EQToneRegion.bandWeights.count == EQToneRegion.allCases.count)
        for band in 0 ..< EQBands.count {
            let sum = EQToneRegion.bandWeights.reduce(Float(0)) { $0 + $1[band] }
            #expect(abs(sum - 1) < 1e-6, "Σ weights at band \(band) = \(sum)")
        }
    }

    @Test("TONE-03: every weight lies in 0…1")
    func weightsAreFractions() {
        for region in EQToneRegion.allCases {
            for hz in Self.probeHz {
                let weight = region.weight(atHz: hz)
                #expect(weight >= 0 && weight <= 1, "\(region) at \(hz) Hz = \(weight)")
            }
        }
    }

    @Test("TONE-04: each region owns its band — full weight well inside it, none well outside")
    func regionsOwnTheirRanges() {
        // A frequency at least half an octave from every crossover sits in exactly one region.
        let owned: [(EQToneRegion, Double)] = [
            (.bass, 40), (.body, 274), (.mids, 1000), (.presence, 3464), (.air, 14000),
        ]
        for (owner, hz) in owned {
            for region in EQToneRegion.allCases {
                let expected: Double = region == owner ? 1 : 0
                #expect(abs(region.weight(atHz: hz) - expected) < 1e-12, "\(region) at \(hz) Hz")
            }
        }
    }

    @Test("TONE-05: a crossover is shared half-and-half by its two neighbours")
    func crossoversSplitEvenly() {
        let neighbours: [Double: (below: EQToneRegion, above: EQToneRegion)] = [
            150: (.bass, .body), 500: (.body, .mids), 2000: (.mids, .presence), 6000: (.presence, .air),
        ]
        for (hz, (below, above)) in neighbours {
            #expect(abs(below.weight(atHz: hz) - 0.5) < 1e-12)
            #expect(abs(above.weight(atHz: hz) - 0.5) < 1e-12)
        }
    }
}
