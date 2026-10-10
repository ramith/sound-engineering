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

    /// The C++ graphic-EQ designer keeps its own copy of the centres (Sources/AudioDSP/EQ/
    /// GraphicEQBands.h): it designs the cascade, and the C++ gate cannot read Swift. Its gate
    /// (EQ_Bands_MatchKit, Tests/EqDesignerTests.inc) pins that copy to this same table, so the
    /// bands the UI draws and the bands the engine plays can only change together.
    @Test("BANDS-04: the exact centres equal the C++ designer's, bit for bit")
    func centresMatchTheDesigner() {
        let designerCentresHz: [Double] = [
            19.952623149688797, 25.118864315095809, 31.622776601683793, 39.810717055349734,
            50.118723362727252, 63.095734448019329, 79.432823472428169, 100,
            125.89254117941675, 158.48931924611142, 199.52623149688787, 251.18864315095823,
            316.22776601683796, 398.10717055349733, 501.18723362727246, 630.957344480193,
            794.3282347242822, 1000, 1258.9254117941675, 1584.893192461114,
            1995.2623149688789, 2511.8864315095821, 3162.2776601683795, 3981.0717055349774,
            5011.8723362727251, 6309.5734448019302, 7943.2823472428217, 10000,
            12589.254117941688, 15848.931924611141, 19952.623149688789,
        ]
        #expect(EQBands.centreHz == designerCentresHz)
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
