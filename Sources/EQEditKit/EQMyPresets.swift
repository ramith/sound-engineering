// EQMyPresets — saving, renaming and deleting the user's own presets (Sprint EQ, EQ4). Each one changes
// the slots and My Presets together (`eqStateV2` and `eqCustomPresetsV1`), so it lives here, tested,
// and the view model only sends and persists the result. Names go through `EQPresetName`.

public enum EQMyPresets {
    /// Saves `source` — what played when the Save sheet opened — as the My Preset `typed` names, the
    /// Tone baked in, replacing one of that name (in any case, under its own name). Its slot, the one it
    /// came from (break-it C1), then plays the preset unedited. Returns the name stored, or `nil` when
    /// the name is refused and nothing changes.
    @discardableResult
    public static func save(_ source: EQSaveSource, as typed: String,
                            store: inout EQStore, myPresets: inout [String: [Float]]) -> String? {
        let name: String
        switch EQPresetName.check(typed, among: myPresets.keys) {
        case let .new(new): name = new
        case let .replaces(existing): name = existing
        case .invalid: return nil
        }
        myPresets[name] = store.save(source, as: name).points
        return name
    }

    /// Renames the My Preset `name` to what `typed` names; every slot playing it follows. Returns the new
    /// name, or `nil` when there is no such preset or the name is refused (and nothing changes).
    @discardableResult
    public static func rename(_ name: String, to typed: String,
                              store: inout EQStore, myPresets: inout [String: [Float]]) -> String? {
        guard let points = myPresets[name],
              case let .new(newName) = EQPresetName.check(typed, among: myPresets.keys, renaming: name)
        else { return nil }
        guard newName != name else { return name }
        myPresets[name] = nil
        myPresets[newName] = points
        store.repointMyPresets { $0 == name ? newName : $0 }
        return newName
    }

    /// Deletes the My Preset `name`. A slot playing it keeps its sound, as an edited Flat.
    public static func delete(_ name: String, store: inout EQStore, myPresets: inout [String: [Float]]) {
        guard myPresets.removeValue(forKey: name) != nil else { return }
        store.repointMyPresets { $0 == name ? nil : $0 }
    }
}
