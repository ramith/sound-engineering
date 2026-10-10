// BANDS — the shared 31-band grid: exact 1/3-octave centres for the maths, ISO 266 nominal
// centres for the UI and the presets, and the three dB limits of the contract.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQBands — the 31-band grid")
struct EQBandsTests {
    @Test("BANDS-01: 31 bands, exact centres at 10^(1.3 + 0.1·m)")
    func exactCentres() {
        #expect(EQBands.count == 31)
        #expect(EQBands.centreHz.count == EQBands.count)
        for (band, hz) in EQBands.centreHz.enumerated() {
            #expect(abs(log10(hz) - (1.3 + 0.1 * Double(band))) < 1e-12)
        }
    }

    @Test("BANDS-02: the nominal centres are ISO 266's, each within 1 % of its exact centre")
    func nominalCentres() {
        #expect(EQBands.nominalHz.count == EQBands.count)
        #expect(EQBands.nominalHz.first == 20 && EQBands.nominalHz.last == 20000)
        for (nominal, exact) in zip(EQBands.nominalHz, EQBands.centreHz) {
            #expect(abs(nominal / exact - 1) < 0.01, "\(nominal) Hz vs \(exact) Hz")
        }
    }

    @Test("BANDS-03: the contract's limits — a point ±12, the base layer ±24, a Tone region ±12")
    func limits() {
        #expect(EQBands.pointLimitDb == 12)
        #expect(EQBands.baseLimitDb == 24)
        #expect(EQBands.toneLimitDb == 12)
        #expect(Float(13).clamped(within: 12) == 12)
        #expect(Float(-13).clamped(within: 12) == -12)
        #expect(Float(-3.5).clamped(within: 12) == -3.5)
    }
}
