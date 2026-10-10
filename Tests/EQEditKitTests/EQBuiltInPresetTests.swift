// PRESET — the built-in presets (review F13; decisions 30–32): stable persisted ids that never change,
// display names kept separate ("Loudness" shows as "Bass & Treble"), Studio retired for Bass Boost under
// a new id with a stored "Studio" loading as Flat, and the re-voiced shapes — each a Tone setting over a
// flat base, pinned to the points the re-voice measured and to the C++ accuracy gate's table.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQBuiltInPreset — stable ids, names, the re-voiced shapes")
struct EQBuiltInPresetTests {
    @Test("PRESET-01: the stable ids — the strings the app has always persisted, and Bass Boost's new one")
    func stableIds() {
        // `eqLiveStateV1.presetRaw` and `eqStateV2` hold these exact strings on users' machines.
        #expect(EQBuiltInPreset.allCases.map(\.rawValue)
            == ["Flat", "Presence", "Clarity", "Warm", "Loudness", "Vocal", "BassBoost"])
        #expect(EQBuiltInPreset.allCases.allSatisfy { $0.id == $0.rawValue })
        #expect(EQBuiltInPreset(rawValue: "Warm") == .warm)
    }

    @Test("PRESET-02: the display names (decisions 31–32)")
    func displayNames() {
        #expect(EQBuiltInPreset.allCases.map(\.displayName)
            == ["Flat", "Presence", "Clarity", "Warm", "Bass & Treble", "Vocal", "Bass Boost"])
    }

    @Test("PRESET-03: a preset encodes as its stable id")
    func codableAsId() throws {
        let data = try JSONEncoder().encode([EQBuiltInPreset.loudness, .bassBoost])
        #expect(String(bytes: data, encoding: .utf8) == #"["Loudness","BassBoost"]"#)
        #expect(try JSONDecoder().decode([EQBuiltInPreset].self, from: data) == [.loudness, .bassBoost])
    }

    @Test("PRESET-04: every preset has one finite point per band, inside ±12 dB; Flat is all 0")
    func pointsAreWellFormed() {
        for preset in EQBuiltInPreset.allCases {
            #expect(preset.points.count == EQBands.count, "\(preset)")
            #expect(preset.points.allSatisfy { $0.isFinite && abs($0) <= 12 }, "\(preset)")
        }
        #expect(EQBuiltInPreset.flat.points.allSatisfy { $0 == 0 && $0.sign == .plus })
    }

    @Test("PRESET-05: each preset is its Tone setting — every region's level where that region alone reaches")
    func shapesAreToneSettings() throws {
        // A nominal centre at least half an octave from every crossover, so one region owns it.
        let owned: [(EQToneRegion, Double)] = [(.bass, 40), (.body, 250), (.mids, 1000), (.presence, 3150),
                                               (.air, 12500)]
        for preset in EQBuiltInPreset.allCases {
            for (region, hz) in owned {
                let band = try #require(EQBands.nominalHz.firstIndex(of: hz))
                #expect(preset.points[band] == preset.tone[region] ?? 0, "\(preset) at \(hz) Hz")
            }
            // Smooth, evidence-sized shapes (Olive/Harman): no step over 2.5 dB between neighbours,
            // lifts of at most +5 dB, cuts of at most 2 dB.
            let steps = zip(preset.points, preset.points.dropFirst()).map { abs($1 - $0) }
            #expect(steps.allSatisfy { $0 <= 2.5 + 1e-5 }, "\(preset)")
            #expect(preset.points.allSatisfy { $0 <= 5 && $0 >= -2 }, "\(preset)")
        }
        #expect(EQBuiltInPreset.warm.tone == [.bass: 3, .body: 2, .presence: -1.5, .air: -2])
    }

    /// The re-voice's measured points (docs/design/eq-lens/plan/preset-revoice.md §1), which the C++
    /// designer's accuracy gate (EQ_ACGE_Presets_Tone_Smooth, Tests/EqDesignerTests.inc) pins in its own
    /// table: re-voice a preset and both tables change together, and the gate re-checks its accuracy.
    @Test("PRESET-06: the points are exactly the re-voice's, and the ones the C++ accuracy gate pins")
    func pointsMatchTheRevoiceAndTheGate() {
        let run = { (value: Float, count: Int) in [Float](repeating: value, count: count) }
        let gate: [EQBuiltInPreset: [Float]] = [
            .flat: run(0, 31),
            .presence: run(0, 19) + [0.3, 1.8, 3.2, 3.5, 3.5, 3.2, 2.0] + run(1, 5),
            .clarity: run(0, 8) + [-0.3, -1.3, -2.0, -2.0, -2.0, -1.8, -1.0, -0.1, 0.0, 0.0, 0.0, 0.1, 0.8, 1.4,
                                   1.5, 1.5, 1.7, 2.4] + run(3, 5),
            .warm: run(3, 8) + [2.9, 2.4, 2.0, 2.0, 2.0, 1.8, 1.0, 0.1, 0.0, 0.0, 0.0, -0.1, -0.8, -1.4, -1.5,
                                -1.5, -1.6, -1.8] + run(-2, 5),
            .loudness: run(5, 8) + [4.3, 1.8, 0.1] + run(0, 8) + [0.1, 0.5, 0.9, 1.0, 1.0, 1.3, 2.5] + run(3.5, 5),
            .vocal: run(-2, 8) + [-1.9, -1.7, -1.5, -1.5, -1.5, -1.2, 0.2, 1.8, 2.0, 2.0, 2.0, 2.1, 2.5, 2.9, 3.0,
                                  3.0, 2.6, 1.2, 0.1] + run(0, 4),
            .bassBoost: run(5, 8) + [4.5, 2.4, 1.1, 1.0, 1.0, 0.9, 0.5, 0.1] + run(0, 15),
        ]
        #expect(Set(gate.keys) == Set(EQBuiltInPreset.allCases))
        for (preset, points) in gate {
            #expect(points.count == EQBands.count, "\(preset) table")
            #expect(preset.points == points, "\(preset): \(preset.points)")
        }
    }

    @Test("PRESET-07: a stored \"Studio\" loads as Flat — unedited, edited (its curve kept), pinned, and from v1")
    func retiredStudioLoadsAsFlat() throws {
        #expect(try EQFixture.decode(EQBuiltInPreset.self, #""Studio""#) == .flat)
        #expect(try EQFixture.decode(EQPresetRef.self, #"{"builtIn":"Studio"}"#) == .builtIn(.flat))
        #expect(throws: DecodingError.self) { try EQFixture.decode(EQBuiltInPreset.self, #""Podcast""#) }
        let unedited = #"{"preset":{"builtIn":"Studio"},"isOn":true}"#
        #expect(try EQFixture.decode(EQState.self, unedited) == .flat)
        // An edited Studio keeps the user's curve, as an edited Flat.
        let curve = EQFixture.curve([28: 2, 29: 2, 30: 2, 20: 4])
        let edited = try #"{"preset":{"builtIn":"Studio"},"isOn":true,"curve":"# + EQFixture.json(curve) + "}"
        let decoded = try EQFixture.decode(EQState.self, edited)
        #expect(decoded.preset == .builtIn(.flat) && decoded.points == curve.points)
        // Shared and pinned alike.
        let pin = #""p":{"key":{"uid":"p","name":"P"},"state":"# + unedited + "}"
        let stored = #"{"version":2,"shared":"# + unedited + #","pinned":{"# + pin + "}}"
        let store = try EQFixture.decode(EQStore.self, stored)
        #expect(store[slot: nil] == .flat && store[slot: "p"] == .flat)
        // v1's "Studio" migrates to Flat, unedited.
        let v1 = try JSONSerialization.data(withJSONObject: [
            "presetRaw": "Studio", "bandGains": [Float](repeating: 0, count: 27) + [0.97, 1.7, 2, 2],
        ])
        #expect(EQMigration.store(fromV1: v1, customPresets: [:])[slot: nil] == .flat)
    }

    @Test("PRESET-08: every unedited built-in, stored or migrated, plays the new voicing — and isn't Edited")
    func uneditedUsersHearTheRevoice() throws {
        for preset in EQBuiltInPreset.allCases {
            // eqStateV2 as an earlier build wrote it: an unedited built-in is a reference, with no points.
            let stored = #"{"preset":{"builtIn":"\#(preset.rawValue)"},"isOn":true}"#
            let state = try EQFixture.decode(EQState.self, stored)
            #expect(state.points == preset.points, "\(preset)")
            #expect(!state.isEdited(myPresets: [:]), "\(preset)")
            // From v1, whose built-in was chosen and untouched: its v1 gains don't matter.
            let v1 = try JSONSerialization.data(withJSONObject: [
                "presetRaw": preset.rawValue, "bandGains": [Float](repeating: 9, count: EQBands.count),
            ])
            let migrated = EQMigration.store(fromV1: v1, customPresets: [:])[slot: nil]
            #expect(migrated.points == preset.points && !migrated.isEdited(myPresets: [:]), "\(preset)")
        }
    }
}
