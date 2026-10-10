// EQBuiltInPreset — the shipped presets and their 31 points (Sprint EQ, EQ0; moved here from
// the app's `Models/EQPreset.swift`, review F13). The single source of truth for every preset
// shape: the editor, the picker and the engine all read `points`.
//
// IDENTITY vs NAME: the raw value is the preset's stable id — persisted, so it never changes.
// It keeps the strings the app has always stored ("Flat", "Warm", "Loudness", …), so saved state
// decodes with no alias. What the user sees is `displayName`, which can change freely: "Loudness"
// shows as "Bass & Treble" (decision 31). A preset whose meaning changes gets a new id instead:
// Studio's slot is now Bass Boost (decision 32), and a stored "Studio" loads as Flat (`retired`).
//
// THE VOICING (decision 30; docs/design/eq-lens/plan/preset-revoice.md). Every preset is a Tone
// setting over a flat base — "Warm = Bass +3, Body +2, Presence −1.5, Air −2" — so each shape is as
// smooth as the Tone macros, with no narrow peaks, and reads in the Tone card's own words. The points
// are derived here from that setting, never pasted, so a shape and its Tone description can't drift
// apart: the Tone weights (`EQToneRegion`) at the nominal ISO centres, where the built-ins have
// always been voiced, rounded to 0.1 dB — exactly the points the re-voice measured. PRESET-06 pins
// them to the C++ accuracy gate's table, so re-voicing a preset re-runs that gate.

import Foundation

public enum EQBuiltInPreset: String, CaseIterable, Identifiable, Sendable {
    /// No change: the recording as it is.
    case flat = "Flat"

    /// Voices and lead instruments step forward, with a little more bite.
    case presence = "Presence"

    /// Cleaner and more open: a touch less boxiness, a touch more top.
    case clarity = "Clarity"

    /// Fuller and softer: a cosy, darker balance.
    case warm = "Warm"

    /// "Bass & Treble" (decision 31): punchier and livelier, the classic smile. Its stored id is the
    /// one v1 wrote, "Loudness"; "Low Volume" would have clashed with S14's loudness compensation.
    case loudness = "Loudness"

    /// Singing and speech come through clearly, with less low-end mud under them.
    case vocal = "Vocal"

    /// Deeper bass for small speakers or bass lovers; everything else untouched. It takes Studio's
    /// slot under a new id (decision 32).
    case bassBoost = "BassBoost"

    public var id: String {
        rawValue
    }

    /// The name shown to the user. Separate from the stable id (`rawValue`).
    public var displayName: String {
        switch self {
        case .flat: "Flat"
        case .presence: "Presence"
        case .clarity: "Clarity"
        case .warm: "Warm"
        case .loudness: "Bass & Treble"
        case .vocal: "Vocal"
        case .bassBoost: "Bass Boost"
        }
    }

    /// The preset as a Tone setting over a flat base (dB per region; a region left out is 0).
    var tone: [EQToneRegion: Float] {
        switch self {
        case .flat: [:]
        case .presence: [.presence: 3.5, .air: 1]
        case .clarity: [.body: -2, .presence: 1.5, .air: 3]
        case .warm: [.bass: 3, .body: 2, .presence: -1.5, .air: -2]
        case .loudness: [.bass: 5, .presence: 1, .air: 3.5]
        case .vocal: [.bass: -2, .body: -1.5, .mids: 2, .presence: 3]
        case .bassBoost: [.bass: 5, .body: 1]
        }
    }

    /// The preset's 31 points (dB), one per band.
    public var points: [Float] {
        Self.pointsByPreset[self] ?? EQCurve.flat.points
    }

    /// Every preset's points, derived once from its Tone setting (see the file comment).
    private static let pointsByPreset: [EQBuiltInPreset: [Float]] = Dictionary(
        uniqueKeysWithValues: allCases.map { preset in
            (preset, EQBands.nominalHz.map { preset.point(atHz: $0) })
        }
    )

    /// The point at `hz`: Σ tone · weight there, to the tenth of a dB (ties to even, as the re-voice
    /// rounded), with a cut that rounds to nothing a plain 0, never −0.
    private func point(atHz hz: Double) -> Float {
        let db = EQToneRegion.allCases.reduce(0.0) { sum, region in
            sum + Double(tone[region] ?? 0) * region.weight(atHz: hz)
        }
        let tenths = (db * 10).rounded(.toNearestOrEven) / 10
        return tenths == 0 ? 0 : Float(tenths)
    }
}

// MARK: - Stored ids (the current ones, and the retired ones' replacements)

extension EQBuiltInPreset: Codable {
    /// Ids of retired built-ins, and what a stored one loads as: a saved "Studio" plays Flat, which is
    /// close to what its users heard under the old engine (decision 32). They stay reserved, so no My
    /// Preset takes one (`EQPresetName`).
    static let retired: [String: EQBuiltInPreset] = ["Studio": .flat]

    /// The built-in a stored id names in this build — its own, or a retired one's replacement; `nil`
    /// for an id no build of this one knows (a newer build's preset).
    init?(storedID: String) {
        guard let preset = Self(rawValue: storedID) ?? Self.retired[storedID] else { return nil }
        self = preset
    }

    /// Decodes a stored id (`init(storedID:)`); an unknown one throws, and the state holding it falls
    /// back as `EQState` decides. Encoding writes the id itself (`rawValue`).
    public init(from decoder: any Decoder) throws {
        let id = try decoder.singleValueContainer().decode(String.self)
        guard let preset = Self(storedID: id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "No built-in preset has the id \(id)"))
        }
        self = preset
    }
}
