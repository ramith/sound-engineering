// PRESET — the built-in presets moved into the kit (review F13): stable persisted ids that
// never change, display names kept separate, and the same shapes the app has always played
// (evaluated at the nominal ISO centres).

import EQEditKit
import Foundation
import Testing

@Suite("EQBuiltInPreset — stable ids and shapes")
struct EQBuiltInPresetTests {
    @Test("PRESET-01: the stable ids are the strings the app has always persisted")
    func stableIds() {
        // `eqLiveStateV1.presetRaw` and the per-output map hold these exact strings on users'
        // machines; changing one would silently turn that user's preset into "Custom".
        #expect(EQBuiltInPreset.allCases.map(\.rawValue)
            == ["Flat", "Presence", "Clarity", "Warm", "Loudness", "Vocal", "Studio"])
        #expect(EQBuiltInPreset.allCases.allSatisfy { $0.id == $0.rawValue })
        #expect(EQBuiltInPreset(rawValue: "Warm") == .warm)
    }

    @Test("PRESET-02: the display names are today's names")
    func displayNames() {
        #expect(EQBuiltInPreset.allCases.map(\.displayName)
            == ["Flat", "Presence", "Clarity", "Warm", "Loudness", "Vocal", "Studio"])
    }

    @Test("PRESET-03: a preset encodes as its stable id")
    func codableAsId() throws {
        let data = try JSONEncoder().encode([EQBuiltInPreset.loudness])
        #expect(String(bytes: data, encoding: .utf8) == #"["Loudness"]"#)
        #expect(try JSONDecoder().decode([EQBuiltInPreset].self, from: data) == [.loudness])
    }

    @Test("PRESET-04: every preset has one finite point per band, inside ±12 dB; Flat is all 0")
    func pointsAreWellFormed() {
        for preset in EQBuiltInPreset.allCases {
            #expect(preset.points.count == EQBands.count, "\(preset)")
            #expect(preset.points.allSatisfy { $0.isFinite && abs($0) <= 12 }, "\(preset)")
        }
        #expect(EQBuiltInPreset.flat.points.allSatisfy { $0 == 0 })
    }

    @Test("PRESET-05: the shapes are unchanged — their landmark values at the ISO centres")
    func landmarkValues() throws {
        let landmarks: [EQBuiltInPreset: [Double: Float]] = [
            .presence: [2000: 8, 4000: 0, 800: 0], // the bell's peak; it closes at 4 kHz
            .clarity: [8000: 6],
            .warm: [20: Float(12 * (1 - exp(-log10(20.0) / 1.5))), 2500: 0],
            .loudness: [20: 4, 12500: 3],
            .vocal: [3150: 6],
            .studio: [16000: 2, 8000: 0],
        ]
        for (preset, values) in landmarks {
            for (hz, db) in values {
                let band = try #require(EQBands.nominalHz.firstIndex(of: hz))
                #expect(abs(preset.points[band] - db) <= 1e-5, "\(preset) at \(hz) Hz = \(preset.points[band])")
            }
        }
    }

    /// The C++ designer's accuracy gate (EQ_ACGE_Presets_Tone_Smooth, Tests/EqDesignerTests.inc:
    /// every preset plays within 0.084 dB of its points at 44.1–192 kHz) runs on its own copy of
    /// these points. Pinning them here keeps that gate testing the presets the app ships: re-voice
    /// a preset and both tables change together, and the gate re-checks its accuracy.
    @Test("PRESET-06: the points are exactly the ones the C++ accuracy gate pins")
    func pointsMatchTheDesignerGate() {
        let zeros = { (count: Int) in [Float](repeating: 0, count: count) }
        let gate: [EQBuiltInPreset: [Float]] = [
            .presence: zeros(18) + [
                3.8752439, 6.99874878, 8, 6.99874878, 4.12249899, 9.79717482e-16, 3.49937439, 2.06124949,
            ] + zeros(5),
            .clarity: zeros(18) + [
                1.00658441, 2.08575392, 3, 3.82920933, 4.57333708, 5.19615221, 5.62580061, 5.90257025, 6,
                3.49937439, 2.1228106,
            ] + zeros(2),
            .warm: [
                6.95925808, 7.27462626, 7.58047199, 7.87582207, 8.13384724, 8.38407993, 8.6257267,
                8.83683395, 9.03473473, 9.23927498, 9.41199684, 9.57391262, 9.73093891, 9.88257694,
                10.0150509, 7.33586168, 6.54984617, 5.73225069, 4.85224533, 3.84244251, 2.9430356,
            ] + zeros(10),
            .loudness: [
                4, 3.97630811, 3.90212274, 3.7733438, 3.60674, 3.38917542, 3.11906195, 2.82842708,
                2.50428677, 2.11130285, 1.72957408, 1.32735682, 0.894262433, 0.434711725, 2.44929371e-16,
            ] + zeros(8) + [0.806700289, 1.50767219, 2.13093019, 2.62027121, 2.90351629, 3, 3, 3],
            .vocal: zeros(15) + [
                1.1757797, 2.34269428, 3.34593296, 4.22819042, 5.02495384, 5.55473375, 5.88366747, 6,
                5.52024317, 4.27103186, 2.35093927,
            ] + zeros(5),
            .studio: zeros(27) + [0.968810976, 1.69511616, 2, 2],
        ]
        for (preset, points) in gate {
            #expect(points.count == EQBands.count, "\(preset) table")
            #expect(preset.points == points, "\(preset)")
        }
    }
}
