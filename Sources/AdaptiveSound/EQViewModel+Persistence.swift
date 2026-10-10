import EQEditKit
import Foundation

// MARK: - EQViewModel persistence

/// The EQ persists through the injected `defaults` (`AppDataLocation`'s) under two keys:
///   `eqStateV2`         — JSON `EQStore`: every slot, written whole (one value, so the slots can
///                         never disagree on disk) on each discrete action and at stroke end, never
///                         per drag sample;
///   `eqCustomPresetsV1` — JSON `[String: [Float]]`: My Presets, unchanged from v1 (a downgrade
///                         still reads it).
/// v1's `eqLiveStateV1` is read once, by the migration, and left in place for one release so a
/// downgrade still finds its EQ. v1's `eqOutputPresetMapV1` was never written and is dropped.
extension EQViewModel {
    private enum Key {
        static let store = "eqStateV2"
        static let myPresets = "eqCustomPresetsV1"
        static let liveStateV1 = "eqLiveStateV1"
    }

    /// Write every slot.
    func persist() {
        Self.write(store, to: defaults)
    }

    /// Write My Presets.
    func persistMyPresets() {
        guard let data = try? JSONEncoder().encode(customPresets) else { return }
        defaults.set(data, forKey: Key.myPresets)
    }

    /// My Presets as stored; one with the wrong count or a non-finite value is skipped.
    static func loadMyPresets(from defaults: UserDefaults) -> [String: [Float]] {
        guard let data = defaults.data(forKey: Key.myPresets),
              let decoded = try? JSONDecoder().decode([String: [Float]].self, from: data)
        else { return [:] }
        return decoded.filter { $0.value.count == EQBands.count && $0.value.allSatisfy(\.isFinite) }
    }

    /// The stored slots: `eqStateV2`, or on the first launch after the upgrade the v1 EQ migrated
    /// (`EQMigration`) and written at once, so it migrates once. Unreadable v2 data plays Flat and
    /// stays on disk until the next write. A slot on a My Preset that no longer exists keeps its
    /// curve as an edited Flat.
    static func loadStore(from defaults: UserDefaults, myPresets: [String: [Float]]) -> EQStore {
        var store: EQStore
        if let data = defaults.data(forKey: Key.store) {
            do {
                store = try JSONDecoder().decode(EQStore.self, from: data)
            } catch {
                logUX("EQ persistence: eqStateV2 unreadable (\(error.localizedDescription)) — playing Flat")
                store = EQStore(shared: .flat)
            }
        } else {
            store = EQMigration.store(fromV1: defaults.data(forKey: Key.liveStateV1), customPresets: myPresets)
            write(store, to: defaults)
            logUX("EQ persistence: migrated eqLiveStateV1 → eqStateV2")
        }
        store.repointMyPresets { myPresets[$0] == nil ? nil : $0 }
        logUX("EQ persistence: loaded \(myPresets.count) My Preset(s), "
            + "shared='\(store[slot: nil].preset.displayName)'")
        return store
    }

    private static func write(_ store: EQStore, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        defaults.set(data, forKey: Key.store)
    }
}
