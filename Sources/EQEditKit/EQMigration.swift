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
//
// A DOWNGRADE, THEN AN UPGRADE AGAIN (break-it B1). `eqLiveStateV1` stays on disk for one release,
// so a v1 build still plays; a v1 build run in between writes its EQ there and never touches
// `eqStateV2`. The store therefore remembers the fingerprint of the v1 blob it last took in, and
// at load `catchUp` compares it with the blob on disk:
//   - the same blob, or none: nothing happened in a v1 build — the store is current;
//   - another blob: the user chose or edited the EQ in a v1 build after this store was written, so
//     that is the latest EQ they made — the shared slot is migrated from it again (rules 1–3). Pins
//     stay: v1 has no per-output memory to replace them with;
//   - a store from before this rule (no fingerprint) can't tell which came later: it records the
//     blob's fingerprint and keeps its own state, so an edit made in v2 is never discarded on a guess.

import Foundation

public enum EQMigration {
    /// The v2 store for a user whose last EQ was the v1 blob `live` (`eqLiveStateV1`), given their
    /// saved presets (`eqCustomPresetsV1`, name → points). It records the blob's fingerprint.
    public static func store(fromV1 live: Data?, customPresets: [String: [Float]]) -> EQStore {
        var store = EQStore(shared: state(fromV1: live, customPresets: customPresets))
        store.v1Fingerprint = live.map(fingerprint(of:))
        return store
    }

    /// `store` caught up with the v1 blob on disk (`live`): the shared slot migrated again when a v1
    /// build wrote another EQ since the store took the last one in; otherwise `store` unchanged but
    /// for the fingerprint it records (see the file comment for the rule).
    public static func catchUp(_ store: EQStore, withV1 live: Data?, customPresets: [String: [Float]]) -> EQStore {
        guard let live else { return store }
        let current = fingerprint(of: live)
        guard store.v1Fingerprint != current else { return store }
        var caughtUp = store
        if store.v1Fingerprint != nil {
            caughtUp[slot: nil] = state(fromV1: live, customPresets: customPresets)
        }
        caughtUp.v1Fingerprint = current
        return caughtUp
    }

    /// The state the v1 blob `live` migrates to (rules 1–3).
    static func state(fromV1 live: Data?, customPresets: [String: [Float]]) -> EQState {
        guard let live, let v1 = try? JSONDecoder().decode(V1LiveState.self, from: live),
              EQCurve.isWellFormed(v1.bandGains)
        else { return .flat }
        // Rule 1, through the stored-id rule: a retired id plays its replacement (v1's "Studio" is
        // Flat, decision 32). An id no build knows was played as an edit in v1: rules 2–3.
        if let builtIn = v1.presetRaw.flatMap(EQBuiltInPreset.init(storedID:)) {
            return EQState(preset: .builtIn(builtIn), curve: nil)
        }
        let curve = EQCurve(points: v1.bandGains)
        // Rule 2: the first matching name, so duplicate saved shapes resolve the same way every time.
        let saved = customPresets.sorted { $0.key < $1.key }.first { !curve.isEdited(against: $0.value) }
        // Rule 3 is the same state with Flat as its preset (canonical: a flat v1 curve is plain Flat).
        let preset = saved.map { EQPresetRef.mine($0.key) } ?? .builtIn(.flat)
        return EQState(preset: preset, curve: curve)
    }

    /// A v1 blob's fingerprint: the 64-bit FNV-1a hash of its bytes, in hex. Stable across launches
    /// and builds (unlike `Hasher`, seeded per process); it only has to tell a changed blob from the
    /// same one.
    static func fingerprint(of v1: Data) -> String {
        let hash = v1.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
        return String(hash, radix: 16)
    }
}

/// `eqLiveStateV1` as v1 wrote it: `{"presetRaw": "Warm", "bandGains": [31 floats]}`, with
/// `presetRaw` omitted once the user had edited.
private struct V1LiveState: Decodable {
    let presetRaw: String?
    let bandGains: [Float]
}
