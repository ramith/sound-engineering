// EQState — what one EQ slot remembers (Sprint EQ, EQ3a; amendment 8): the preset it plays, its
// own curve when it isn't simply that preset, and whether the EQ is on.
//
// AN UNEDITED BUILT-IN IS A REFERENCE. `curve == nil` means "this built-in's CURRENT points", so a
// re-voiced built-in (a later build changing its shape) reaches every slot that never edited it,
// shared and pinned alike, while an edited slot keeps exactly what the user made. The form is
// canonical: whenever a built-in's curve plays its preset again (Tone at 0, every point within
// 0.05 dB) it drops back to the reference, so equal sounds compare equal and the stored state
// omits the curve. A My Preset always carries its curve: it can be renamed, overwritten or deleted
// under the slot.
//
// What plays is derived, never stored: `points` (and, from the designer, the engine's response).

public struct EQState: Equatable, Sendable {
    /// The preset this state is, or was edited from.
    public private(set) var preset: EQPresetRef

    /// This state's own curve; `nil` for an unedited built-in, which plays that preset's current
    /// points.
    private(set) var curve: EQCurve?

    /// Whether the EQ plays at all (Off is a true bypass).
    public var isOn: Bool

    /// Flat, unedited, on: a fresh install, and what a slot that can't be read plays.
    public static let flat = EQState(preset: .builtIn(.flat), curve: nil)

    /// A state in canonical form: a built-in's curve that plays the built-in becomes the
    /// reference; a My Preset with no curve (it has nothing to play) becomes Flat.
    public init(preset: EQPresetRef, curve: EQCurve?, isOn: Bool = true) {
        self.isOn = isOn
        switch preset {
        case let .builtIn(builtIn):
            self.preset = preset
            self.curve = curve.flatMap { $0.isEdited(against: builtIn.points) ? $0 : nil }
        case .mine:
            self.preset = curve == nil ? .builtIn(.flat) : preset
            self.curve = curve
        }
    }

    /// The state of choosing `preset`: its points with Tone at 0, and on (choosing is an edit, and
    /// any edit turns the EQ on). `nil` for a My Preset that no longer exists, or whose points are
    /// not one finite value per band — never a trap.
    public init?(choosing preset: EQPresetRef, myPresets: [String: [Float]]) {
        guard let points = preset.points(myPresets: myPresets), EQCurve.isWellFormed(points) else { return nil }
        self.init(preset: preset, curve: EQCurve(points: points))
    }

    /// The curve this state plays: its own, else its built-in's current points.
    public var resolvedCurve: EQCurve {
        if let curve {
            return curve
        }
        // The canonical form gives only a built-in no curve; anything else would play Flat.
        guard case let .builtIn(builtIn) = preset else { return .flat }
        return EQCurve(points: builtIn.points)
    }

    /// The 31 points this state plays: drawn, and sent to the engine.
    public var points: [Float] {
        resolvedCurve.points
    }

    /// Whether this state plays something other than its preset (the "Edited" rule): any point more
    /// than 0.05 dB from the preset's, or any Tone. A My Preset that no longer exists counts as
    /// edited.
    public func isEdited(myPresets: [String: [Float]]) -> Bool {
        guard let curve else { return false }
        guard let presetPoints = preset.points(myPresets: myPresets) else { return true }
        return curve.isEdited(against: presetPoints)
    }

    /// Plays `curve` from now on. This is an edit: the EQ turns on, and a built-in edited back onto
    /// its own points becomes the reference again.
    public mutating func edit(to curve: EQCurve) {
        self = EQState(preset: preset, curve: curve)
    }

    /// This state saved as the My Preset `name`: the same points with the Tone baked in (decision
    /// 24), on or off as it was.
    public func saved(as name: String) -> EQState {
        EQState(preset: .mine(name), curve: resolvedCurve.baked(), isOn: isOn)
    }

    /// Re-points a My Preset reference: `newName(name)` is the preset's name now, or `nil` once it
    /// is gone. A state left without its preset keeps its curve as an edited Flat, so what it plays
    /// never changes. Built-in states are untouched.
    mutating func repointMyPreset(_ newName: (String) -> String?) {
        guard case let .mine(name) = preset else { return }
        let preset = newName(name).map(EQPresetRef.mine) ?? .builtIn(.flat)
        self = EQState(preset: preset, curve: curve, isOn: isOn)
    }
}

// MARK: - Codable (an unedited built-in omits its curve)

extension EQState: Codable {
    private enum CodingKeys: String, CodingKey {
        case preset, curve, isOn
    }

    /// Decodes into the canonical form, each field on its own so one damaged field never costs the
    /// others (break-it BRK-02):
    /// - a preset this build doesn't know (a newer build's built-in) plays on as an edited Flat with
    ///   its curve kept, or as Flat when it had none;
    /// - a curve outside its limits (wrong counts, non-finite) is dropped: the state falls back to
    ///   its built-in's reference (a My Preset to Flat) and keeps its On/Off — an Off slot stays
    ///   Off, the bit-perfect path (decision 25);
    /// - a missing or unreadable On/Off reads On (the app's default) and keeps the curve.
    /// Only a state that isn't an object at all throws (that slot then plays Flat, `EQStore`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            preset: (try? container.decode(EQPresetRef.self, forKey: .preset)) ?? .builtIn(.flat),
            curve: try? container.decodeIfPresent(EQCurve.self, forKey: .curve),
            isOn: (try? container.decode(Bool.self, forKey: .isOn)) ?? true
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encodeIfPresent(curve, forKey: .curve)
        try container.encode(isOn, forKey: .isOn)
    }
}
