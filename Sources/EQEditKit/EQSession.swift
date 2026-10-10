// EQSession — the EQ as the user edits and hears it, and every decision about it (Sprint EQ; review
// fix round: the view model's decisions had no gate). The slots (`EQStore`), My Presets, the output,
// the drag in progress, a held Compare and the Bring back offer, with one verb per thing the user or
// the system can do. A verb changes the session and returns an `EQOutcome` — what to send, write, log
// and toast — which the app's `EQViewModel` carries out and nothing more. So the rules that span those
// pieces live here, under test:
//
// - every edit writes the CURRENT output's slot, turns the EQ on, and releases a held Compare;
// - a discrete edit (a preset choice, a key step, Save, the switch, a pin) ends a drag first, so it
//   applies to what plays and what is on disk, and the rest of that drag is ignored (`+Stroke`);
// - Esc during a drag puts back everything the drag changed: the curve and the Bring back offer;
// - an output switch sends when the current slot's sound changes, and toasts when the sound differs
//   from what was last heard on an output (`+Slots`, `EQOutputSwitch`).

import Foundation

public struct EQSession: Sendable {
    // MARK: - State

    /// Every slot the EQ remembers, persisted whole as `eqStateV2`.
    public internal(set) var store: EQStore

    /// The user's saved presets (My Presets), name → points; persisted as `eqCustomPresetsV1`.
    public internal(set) var myPresets: [String: [Float]]

    /// The output the sound plays on (`nil` before the first device, and while there is none); its slot
    /// is `current`.
    public internal(set) var output: EQOutputKey?

    /// Compare is held: the song plays without the EQ until it is released (decision 28). Every change
    /// to what plays releases it.
    public internal(set) var isComparing = false

    /// Edits a preset switch set aside, offered back until the next edit (decision 27).
    public internal(set) var bringBack: EQBringBack?

    /// The drag in progress (`+Stroke`).
    var stroke: Stroke?

    /// What last played on an output; `nil` until one has (`EQOutputSwitch`).
    var lastHeard: EQState?

    /// A session over the stored slots and presets, playing on `output`.
    public init(store: EQStore, myPresets: [String: [Float]], output: EQOutputKey? = nil) {
        self.store = store
        self.myPresets = myPresets
        self.output = output
    }

    // MARK: - Derived (never stored)

    /// What the current output plays: its pinned slot, else the shared one.
    public var current: EQState {
        store[slot: store.slotID(for: output)]
    }

    /// The 31 points drawn and sent.
    public var points: [Float] {
        current.points
    }

    /// Whether the engine plays the EQ: it is on, and Compare isn't held.
    public var plays: Bool {
        current.isOn && !isComparing
    }

    /// Whether the current state differs from its preset (the "Edited" rule).
    public var isEdited: Bool {
        current.isEdited(myPresets: myPresets)
    }

    /// The preset as it plays: "Warm", "Warm · edited", "Late Night".
    public var presetLabel: String {
        let name = current.preset.displayName
        return isEdited ? "\(name) · edited" : name
    }

    /// One line for the EQ as it plays: `presetLabel`, or "Off".
    public var summary: String {
        current.isOn ? presetLabel : "Off"
    }

    /// The user's saved presets by name, in the list's order (as Finder sorts names).
    public var myPresetNames: [String] {
        myPresets.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The presets list top to bottom: the built-ins, then My Presets — the rows the arrow keys walk.
    public var presetRows: [EQPresetRef] {
        EQBuiltInPreset.allCases.map(EQPresetRef.builtIn) + myPresetNames.map(EQPresetRef.mine)
    }

    /// The 31 points `preset` plays unedited (its row's curve glyph); flat for a My Preset that is gone.
    public func glyphPoints(for preset: EQPresetRef) -> [Float] {
        EQState(choosing: preset, myPresets: myPresets)?.points ?? EQCurve.flat.points
    }

    // MARK: - Writing (the path every change takes)

    /// Writes `state` into the current output's slot. Any change to what plays releases a held Compare
    /// (decision 28), and is sent.
    mutating func setCurrent(_ state: EQState) -> EQOutcome {
        isComparing = false
        store[slot: store.slotID(for: output)] = state
        return EQOutcome(.send)
    }

    /// An edit: the current slot plays `curve` from now on, the EQ turns on, and edits set aside earlier
    /// are no longer offered back (decision 27).
    mutating func edit(to curve: EQCurve) -> EQOutcome {
        bringBack = nil
        var state = current
        state.edit(to: curve)
        return setCurrent(state)
    }

    // MARK: - Presets, the switch, Reset

    /// Choose a preset: its points, Tone at 0, and the EQ on. Re-choosing the current preset resets it.
    /// Leaving edits behind offers them back. A My Preset that no longer exists is ignored.
    public mutating func choose(_ preset: EQPresetRef) -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        guard let state = EQState(choosing: preset, myPresets: myPresets) else { return ended }
        bringBack = EQBringBack.afterSwitch(from: bringBack, leaving: current, to: preset, myPresets: myPresets)
        return ended.then(setCurrent(state))
            .then(EQOutcome(.saveSlots, log: "EQ preset → '\(preset.displayName)'"))
    }

    /// Reset (the header): the same as re-choosing the preset — its points, Tone at 0, on. It offers
    /// nothing back: resetting is the user's explicit intent.
    public mutating func reset() -> EQOutcome {
        choose(current.preset)
    }

    /// The Equalizer switch. Off is a true bypass at matched loudness (decision 26); the curve is kept.
    public mutating func setOn(_ isOn: Bool) -> EQOutcome {
        guard isOn != current.isOn else { return .none }
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        var state = current
        state.isOn = isOn
        return ended.then(setCurrent(state)).then(EQOutcome(.saveSlots, log: "EQ \(isOn ? "on" : "off")"))
    }

    /// The band at `band` back to its preset's value (⌫ on the graph, VoiceOver's "Reset band"); the
    /// rest of the curve and Tone stay. An edit like any other: persisted per press.
    public mutating func resetBand(_ band: Int) -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        guard let preset = EQState(choosing: current.preset, myPresets: myPresets)?.points,
              preset.indices.contains(band) else { return ended }
        var curve = current.resolvedCurve
        curve.setPoint(band, to: preset[band])
        return ended.then(edit(to: curve)).then(EQOutcome(.saveSlots))
    }

    // MARK: - Compare and Bring back

    /// Compare pressed (decision 28): the song plays without the EQ, at matched loudness, until
    /// `endCompare`. Only while the EQ really plays (`EQAudibleState.canCompare` of `audible`).
    public mutating func beginCompare(when audible: EQAudibleState) -> EQOutcome {
        guard !isComparing, audible.canCompare else { return .none }
        isComparing = true
        return EQOutcome(.send, log: "EQ compare → held")
    }

    /// Compare released: the EQ plays again. Safe to call any time — every release path (Esc, focus
    /// loss, a tab change, the window closing) calls it.
    public mutating func endCompare() -> EQOutcome {
        guard isComparing else { return .none }
        isComparing = false
        return EQOutcome(.send, log: "EQ compare → released")
    }

    /// Bring back the edits a preset switch set aside: the whole slot as it was (preset, base, Tone and
    /// On/Off). The offer is then gone.
    public mutating func bringBackEdits() -> EQOutcome {
        guard let offer = bringBack else { return .none }
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        bringBack = nil
        let restored = ended.then(setCurrent(offer.edits))
        return restored.then(EQOutcome(.saveSlots, log: "EQ bring back edits → '\(presetLabel)'"))
    }
}
