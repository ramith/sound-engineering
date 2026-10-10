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
}
