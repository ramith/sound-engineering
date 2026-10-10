// EQBringBack — "Bring back edits" (Sprint EQ, EQ3; decision 27, ui-plan §4.5). A preset switch away
// from an edited slot happens at once and sets the edits aside, offered back by a message for a few
// seconds — and, with no time limit, from the presets' context menu and a VoiceOver action — until the
// next edit. No prompt and no ⌘Z.

public struct EQBringBack: Equatable, Sendable {
    /// The whole slot as it was before the switch: its preset, its curve (base and Tone) and On/Off.
    public let edits: EQState

    /// Bumps on every switch that offers the edits (again), so the message re-arms its timer.
    public let offer: Int

    /// The offer once the slot switches from `current` to `preset`:
    /// - leaving an edited slot for another preset sets those edits aside (a new offer);
    /// - auditioning presets after that keeps offering the ORIGINAL edits, re-armed: arrowing through
    ///   the list never replaces them with an unedited preset;
    /// - re-choosing the preset already playing (a reset, the user's explicit intent) offers nothing
    ///   new and leaves an earlier offer as it was.
    public static func afterSwitch(from existing: EQBringBack?, leaving current: EQState, to preset: EQPresetRef,
                                   myPresets: [String: [Float]]) -> EQBringBack? {
        let next = (existing?.offer ?? 0) + 1
        if current.offersBringBack(switchingTo: preset, myPresets: myPresets) {
            return EQBringBack(edits: current, offer: next)
        }
        guard let existing, preset != current.preset else { return existing }
        return EQBringBack(edits: existing.edits, offer: next)
    }
}
