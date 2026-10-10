// EQMigration — the v1 → v2 upgrade of the user's EQ (Sprint EQ, EQ3a; review F7/F8). v1 kept
// one live EQ (`eqLiveStateV1`: the chosen built-in's id, or nil once the user edited, plus the
// 31 gains) beside the saved presets (`eqCustomPresetsV1`, unchanged by v2). The never-written
// per-output map (`eqOutputPresetMapV1`) is dropped, so a migrated store has no pins.
//
// In v1, `presetRaw != nil` already meant UNEDITED (any edit set it to nil), so the rules are:
//   1. a v1 built-in is that preset's CURRENT points, unedited — the reference form, so a
//      re-voiced built-in reaches it;
//   2. a v1 edit whose gains equal a saved preset is that My Preset (it was chosen and not touched);
//   3. anything else is an edited Flat that plays exactly the v1 gains.
// The EQ is on in every case (v1 had no Off). Unreadable, miscounted or non-finite v1 data — or none
// at all, a fresh install — is Flat.

import Foundation

public enum EQMigration {
    /// The v2 store for a user whose last EQ was the v1 blob `live` (`eqLiveStateV1`), given their
    /// saved presets (`eqCustomPresetsV1`, name → points).
    public static func store(fromV1 live: Data?, customPresets: [String: [Float]]) -> EQStore {
        guard let live, let v1 = try? JSONDecoder().decode(V1LiveState.self, from: live),
              v1.bandGains.count == EQBands.count, v1.bandGains.allSatisfy(\.isFinite)
        else { return EQStore(shared: .flat) }
        // Rule 1. An id no build knows (e.g. renamed long ago) was played as an edit in v1: rules 2–3.
        if let builtIn = v1.presetRaw.flatMap(EQBuiltInPreset.init(rawValue:)) {
            return EQStore(shared: EQState(preset: .builtIn(builtIn), curve: nil))
        }
        let curve = EQCurve(points: v1.bandGains)
        // Rule 2: the first matching name, so duplicate saved shapes resolve the same way every time.
        let saved = customPresets.sorted { $0.key < $1.key }.first { !curve.isEdited(against: $0.value) }
        // Rule 3 is the same state with Flat as its preset (canonical: a flat v1 curve is plain Flat).
        let preset = saved.map { EQPresetRef.mine($0.key) } ?? .builtIn(.flat)
        return EQStore(shared: EQState(preset: preset, curve: curve))
    }
}

/// `eqLiveStateV1` as v1 wrote it: `{"presetRaw": "Warm", "bandGains": [31 floats]}`, with
/// `presetRaw` omitted once the user had edited.
private struct V1LiveState: Decodable {
    let presetRaw: String?
    let bandGains: [Float]
}
