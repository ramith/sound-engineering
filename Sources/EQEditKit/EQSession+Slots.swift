// EQSession: My Presets, the pin and the output switch (Sprint EQ, EQ4; decision 28; break-it C1, E2).
// Each of these changes slots other than, or as well as, the one playing — so each says for itself
// whether what plays changed (send, and release a held Compare) and what must be written.

import Foundation

public extension EQSession {
    // MARK: - My Presets

    /// What Save would save now: taken when the Save sheet opens (break-it C1).
    func saveSource() -> EQSaveSource {
        store.saveSource(for: output)
    }

    /// `typed` checked as a My Preset's name, for the sheet's inline copy (`renaming` one of them).
    func nameCheck(_ typed: String, renaming: String? = nil) -> EQPresetName.Check {
        EQPresetName.check(typed, among: myPresets.keys, renaming: renaming)
    }

    /// Save `source` as the My Preset `typed` names (replacing one of that name), the Tone baked in: the
    /// slot it came from plays it, unedited — even after the output switched while the sheet was open.
    /// A refused name saves nothing.
    mutating func save(_ source: EQSaveSource, as typed: String) -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        var saved: String?
        let changed = changingSlots { store, myPresets in
            saved = EQMyPresets.save(source, as: typed, store: &store, myPresets: &myPresets)
        }
        guard let saved else { return ended }
        bringBack = nil // Save keeps what plays; edits set aside earlier are no longer offered
        return ended.then(changed)
            .then(EQOutcome([.saveSlots, .saveMyPresets], log: "EQ save preset '\(saved)'"))
    }

    /// Rename the My Preset `name` to what `typed` names; every slot playing it, and edits set aside on
    /// it, follow. A refused name, or the same one, changes nothing.
    mutating func renameMyPreset(_ name: String, to typed: String) -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        var renamed: String?
        let changed = changingSlots { store, myPresets in
            renamed = EQMyPresets.rename(name, to: typed, store: &store, myPresets: &myPresets)
        }
        guard let renamed, renamed != name else { return ended }
        bringBack = bringBack?.repointingMyPresets { $0 == name ? renamed : $0 }
        return ended.then(changed)
            .then(EQOutcome([.saveSlots, .saveMyPresets], log: "EQ rename preset '\(name)' → '\(renamed)'"))
    }

    /// Delete the My Preset `name`. Whatever plays it keeps its sound, as an edited Flat.
    mutating func deleteMyPreset(_ name: String) -> EQOutcome {
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        guard myPresets[name] != nil else { return ended }
        let changed = changingSlots { store, myPresets in
            EQMyPresets.delete(name, store: &store, myPresets: &myPresets)
        }
        bringBack = bringBack?.repointingMyPresets { $0 == name ? nil : $0 }
        return ended.then(changed)
            .then(EQOutcome([.saveSlots, .saveMyPresets], log: "EQ delete preset '\(name)'"))
    }

    // MARK: - The pin (decision 28)

    /// How the current output stands with the pins; `nil` with no output, or one that can't be pinned.
    var outputPin: EQOutputPin? {
        store.pin(for: output)
    }

    /// The "Used on <output>" pin, pressed: pin the current output (it keeps exactly what plays now, and
    /// its edits from then on), or unpin the pin it plays (the shared slot takes it over). Either way
    /// nothing audible changes, so a held Compare stays held. Nothing for an output that can't be pinned.
    mutating func togglePin() -> EQOutcome {
        guard let pin = outputPin else { return .none }
        let ended = endStroke() // a discrete edit ends a drag first (+Stroke)
        let changed = changingSlots { store, _ in
            if pin.isPinned {
                store.unpin(pin.output)
            } else {
                store.pin(pin.output)
            }
        }
        return ended.then(changed)
            .then(EQOutcome(.saveSlots, log: "EQ \(pin.isPinned ? "unpin" : "pin") → '\(pin.output.name)'"))
    }

    /// Applies `change` to the slots and My Presets together. Only a change to what plays releases a
    /// held Compare; what plays is sent either way (the one dispatch is cheap and idempotent).
    private mutating func changingSlots(_ change: (inout EQStore, inout [String: [Float]]) -> Void) -> EQOutcome {
        let before = current
        change(&store, &myPresets)
        if current != before {
            isComparing = false
        }
        return EQOutcome(.send)
    }

    // MARK: - The output switch (Edge 5)

    /// The sound moved to another output (fired only when the UID changes; `nil`: no output now). Its
    /// slot — its pin, else shared — becomes current. A drag stays with its slot: it ends only when the
    /// move changes the slot. A held Compare and edits set aside never carry over. What plays is sent
    /// when it changed, and the toast names the output and its EQ when the sound differs from what was
    /// last heard on an output (`EQOutputSwitch`).
    mutating func outputDidChange(to key: EQOutputKey?) -> EQOutcome {
        let ended = store.isSlotChange(from: output, to: key) ? endStroke() : .none
        let released = endCompare()
        bringBack = nil
        let before = current
        if output != nil {
            lastHeard = before
        }
        output = key
        let change = EQOutputSwitch(before: before, now: current, lastHeard: lastHeard, arrives: key != nil)
        let line = "EQ output → '\(key?.name ?? "none")' slot=\(store.slotID(for: key) ?? "shared")"
        let toast = change.toasts ? key.map { "\($0.name) · \(summary)" } : nil
        return ended.then(released).then(EQOutcome(change.sends ? .send : [], log: line, toast: toast))
    }
}
