// MIGRATE — the v1 → v2 upgrade (EQ3a; review F7/F8), from the formats v1 really wrote:
// `eqLiveStateV1` = JSONEncoder over `EQLiveState { presetRaw: String?; bandGains: [Float] }` (the
// preset omitted once the user had edited), and `eqCustomPresetsV1` = `[String: [Float]]`.
// One fixture per rule, plus the invalid inputs, which all play Flat. The EQ is on in every case.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQMigration — eqLiveStateV1 + eqCustomPresetsV1 → eqStateV2")
struct EQMigrationTests {
    /// A user's saved presets, as `eqCustomPresetsV1` decodes.
    private static let customPresets: [String: [Float]] = [
        "Late Night": EQFixture.points([3: 5, 4: 6, 5: 5, 27: -3]),
        "Podcast": EQFixture.points([14: 3.5, 15: 4]),
    ]

    /// v1's `EQLiveState` (`Models/EQLiveState.swift`, removed by EQ3a), field for field: its
    /// synthesized Codable omits a nil `presetRaw`.
    private struct V1LiveState: Encodable {
        let presetRaw: String?
        let bandGains: [Float]
    }

    /// `eqLiveStateV1` exactly as v1's `persistLiveState` stored it: JSONEncoder over `EQLiveState`.
    private static func v1(_ presetRaw: String?, _ gains: [Float]) -> Data {
        (try? JSONEncoder().encode(V1LiveState(presetRaw: presetRaw, bandGains: gains))) ?? Data()
    }

    private static func migrate(_ live: Data?) -> EQState {
        EQMigration.store(fromV1: live, customPresets: customPresets)[slot: nil]
    }

    @Test("MIGRATE-01: rule 1 — a v1 built-in is that preset's CURRENT points, unedited (stored as a reference)")
    func builtInBecomesReference() throws {
        // v1 stored the gains it played; a later re-voice must still reach this unedited user, so the
        // gains are ignored (here: an older, louder Warm).
        let live = Self.v1("Warm", EQBuiltInPreset.warm.points.map { $0 * 1.2 })
        let store = EQMigration.store(fromV1: live, customPresets: Self.customPresets)
        #expect(store[slot: nil] == EQState(preset: .builtIn(.warm), curve: nil))
        #expect(store[slot: nil].points == EQBuiltInPreset.warm.points)
        let fingerprint = EQMigration.fingerprint(of: live)
        #expect(try EQFixture.json(store) == #"{"pinned":{},"shared":{"isOn":true,"preset":{"builtIn":"Warm"}},"#
            + #""v1Fingerprint":"\#(fingerprint)","version":2}"#)
        // Every built-in id v1 could have stored.
        for preset in EQBuiltInPreset.allCases {
            let migrated = Self.migrate(Self.v1(preset.rawValue, preset.points))
            #expect(migrated == EQState(preset: .builtIn(preset), curve: nil))
        }
    }

    @Test("MIGRATE-02: rule 2 — v1 edits equal to a saved preset are that My Preset, unedited")
    func matchingEditBecomesMyPreset() throws {
        let lateNight = try #require(Self.customPresets["Late Night"])
        let state = Self.migrate(Self.v1(nil, lateNight))
        #expect(state.preset == .mine("Late Night"))
        #expect(state.points == lateNight && state.isOn)
        #expect(!state.isEdited(myPresets: Self.customPresets))
        // Duplicate saved shapes resolve to the first name, every time.
        let duplicates = ["Zed": lateNight, "Alpha": lateNight]
        #expect(EQMigration.store(fromV1: Self.v1(nil, lateNight), customPresets: duplicates)[slot: nil].preset
            == .mine("Alpha"))
    }

    @Test("MIGRATE-03: rule 3 — any other v1 edit is an edited Flat playing exactly the v1 gains")
    func otherEditBecomesEditedFlat() {
        let gains = (0 ..< EQBands.count).map { Float($0 % 7) - 3.5 }
        let state = Self.migrate(Self.v1(nil, gains))
        #expect(state.preset == .builtIn(.flat))
        #expect(state.points == gains && state.isOn)
        #expect(state.isEdited(myPresets: Self.customPresets))
        // A preset id no build knows was played as an edit in v1: rules 2–3 apply.
        #expect(Self.migrate(Self.v1("Bass Boost", gains)) == state)
        #expect(Self.migrate(Self.v1("Bass Boost", Self.customPresets["Podcast"] ?? [])).preset == .mine("Podcast"))
        // v1 gains that are flat are simply Flat.
        #expect(Self.migrate(Self.v1(nil, EQFixture.points([:]))) == .flat)
    }

    @Test("MIGRATE-04: nothing stored (a fresh install), or anything unreadable, plays Flat")
    func invalidPlaysFlat() {
        #expect(Self.migrate(nil) == .flat)
        #expect(Self.migrate(Data("not json".utf8)) == .flat)
        #expect(Self.migrate(Data(#"{"presetRaw":"Warm"}"#.utf8)) == .flat, "no gains")
        #expect(Self.migrate(Self.v1("Warm", [1, 2, 3])) == .flat, "wrong count")
        #expect(Self.migrate(Data(#"{"bandGains":"loud"}"#.utf8)) == .flat)
    }

    @Test("MIGRATE-06: a v1 blob as found on a real machine, byte for byte (Flat, unedited) → Flat by reference")
    func realBlob() throws {
        let zeros = Array(repeating: "0", count: EQBands.count).joined(separator: ",")
        let blob = Data(#"{"bandGains":[\#(zeros)],"presetRaw":"Flat"}"#.utf8)
        #expect(blob.count == 96)
        let store = EQMigration.store(fromV1: blob, customPresets: [:])
        #expect(try EQFixture.json(store) == #"{"pinned":{},"shared":{"isOn":true,"preset":{"builtIn":"Flat"}},"#
            + #""v1Fingerprint":"b0adf57d0b5bc3e2","version":2}"#)
    }

    @Test("MIGRATE-07: the v1 fingerprint is 64-bit FNV-1a — persisted, so pinned to the published vectors")
    func fingerprintIsStable() {
        #expect(EQMigration.fingerprint(of: Data()) == "cbf29ce484222325")
        #expect(EQMigration.fingerprint(of: Data("a".utf8)) == "af63dc4c8601ec8c")
        #expect(EQMigration.fingerprint(of: Data("foobar".utf8)) == "85944171f73967e8")
        #expect(EQMigration.fingerprint(of: Self.v1("Warm", EQBuiltInPreset.warm.points))
            != EQMigration.fingerprint(of: Self.v1("Vocal", EQBuiltInPreset.vocal.points)))
    }

    @Test("MIGRATE-08: downgrade, then upgrade (break-it B1) — an EQ made in a v1 build since wins the shared slot")
    func catchUpWithAV1BuildRunSince() throws {
        // Upgrade from v1 Warm; pin an output; the user downgrades and chooses Vocal in the v1 build,
        // which writes eqLiveStateV1 and nothing else; then this build runs again.
        let warmBlob = Self.v1("Warm", EQBuiltInPreset.warm.points)
        var store = EQMigration.store(fromV1: warmBlob, customPresets: [:])
        let pods = EQOutputKey(uid: "A4-C3:output", modelUID: nil, name: "AirPods Pro")
        let late = EQState(preset: .mine("Late Night"), curve: EQFixture.curve([4: 6]))
        store = EQStore(shared: store[slot: nil], pinned: [pods.uid: .init(key: pods, state: late)],
                        v1Fingerprint: store.v1Fingerprint)
        let vocalBlob = Self.v1("Vocal", EQBuiltInPreset.vocal.points)
        let caughtUp = EQMigration.catchUp(store, withV1: vocalBlob, customPresets: Self.customPresets)
        #expect(caughtUp[slot: nil] == EQState(preset: .builtIn(.vocal), curve: nil))
        #expect(caughtUp[slot: pods.uid] == late, "pins stay: v1 has no per-output memory")
        #expect(caughtUp.v1Fingerprint == EQMigration.fingerprint(of: vocalBlob))
        // Caught up once: the same blob again changes nothing, so the edits made here since survive.
        var edited = caughtUp
        edited[slot: nil] = EQState(preset: .builtIn(.bassBoost), curve: EQFixture.curve([20: 5]))
        #expect(EQMigration.catchUp(edited, withV1: vocalBlob, customPresets: Self.customPresets) == edited)
        // A rule-2 blob catches up as that My Preset.
        let podcast = try #require(Self.customPresets["Podcast"])
        #expect(EQMigration.catchUp(edited, withV1: Self.v1(nil, podcast), customPresets: Self.customPresets)[slot: nil]
            .preset == .mine("Podcast"))
    }

    @Test("MIGRATE-09: no v1 blob, or a store from before the rule, never loses the v2 EQ")
    func catchUpNeverGuesses() {
        let edited = EQState(preset: .builtIn(.bassBoost), curve: EQFixture.curve([20: 5]))
        let current = EQStore(shared: edited, pinned: [:], v1Fingerprint: "cbf29ce484222325")
        #expect(EQMigration.catchUp(current, withV1: nil, customPresets: [:]) == current)
        // Written before the fingerprint existed: it records the blob on disk and keeps its own state.
        let older = EQStore(shared: edited)
        let vocalBlob = Self.v1("Vocal", EQBuiltInPreset.vocal.points)
        let adopted = EQMigration.catchUp(older, withV1: vocalBlob, customPresets: [:])
        #expect(adopted[slot: nil] == edited)
        #expect(adopted.v1Fingerprint == EQMigration.fingerprint(of: vocalBlob))
    }

    @Test("MIGRATE-05: a migrated store has no pins (v1's per-output map was never written)")
    func noPins() {
        #expect(EQMigration.store(fromV1: Self.v1("Vocal", EQBuiltInPreset.vocal.points), customPresets: [:])
            .pinned.isEmpty)
    }
}
