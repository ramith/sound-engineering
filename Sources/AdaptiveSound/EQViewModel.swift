import EQEditKit
import Foundation

// MARK: - EQViewModel

/// The EQ the user edits and hears (the Sprint EQ contract, review §2). It holds one `EQStore` of
/// slots — `shared` for every unpinned output, one per pinned output — and the CURRENT output's
/// slot is `current`. Every editing rule lives in `EQEditKit`; this owns the state, sends it to the
/// engine from ONE place (`publish()`), and persists it (`+Persistence`).
///
/// - Edits: choosing a preset and Save here; the drag and the keyboard step in `+Stroke`; Tone in
///   `+Tone`. Every edit goes through `edit(to:)` or `setCurrent(_:)`, and every edit turns the EQ on.
/// - Outputs: `outputDidChange(to:)`, wired at the composition root (Edge 5), makes the new output's
///   slot current — with the window closed too — and raises `outputToast` when that changes the sound.
/// - The graph's played curve (EQ3, from EQ1a's designer) is a memo on (`points`, the engine's design
///   rate): `points` is its one input from here, so it joins beside `current` with no other change.
@MainActor
@Observable
final class EQViewModel {
    // MARK: - State

    /// Every slot the EQ remembers, persisted whole as `eqStateV2`.
    private(set) var store: EQStore

    /// The user's saved presets (My Presets), name → points; persisted as `eqCustomPresetsV1`.
    private(set) var customPresets: [String: [Float]]

    /// The output the sound plays on (`nil` before the first device); its slot is `current`.
    private(set) var output: EQOutputKey?

    /// An output has played since launch. Only the first one is the launch's, with no toast: after a
    /// gap with no output at all, the next one still says what it plays (break-it E2).
    @ObservationIgnored private var hasSeenOutput = false

    /// The output-switch toast, shown by `EQOutputToast` in the shell overlay for 3 s (UI plan §4.4).
    let outputToast = ShellToastSlot(lifetime: .seconds(3))

    /// The drag in progress (`+Stroke`); internal so that extension can drive it. Never observed.
    @ObservationIgnored var stroke: ActiveStroke?

    /// The Tone region the user is on — a Tone slider hovered, dragged or keyboard-focused
    /// (`EQToneCard`, the one writer) — which the graph shades, with its readout. View state: never
    /// persisted, and `nil` while no Tone slider is in use.
    var highlightedRegion: EQToneRegion?

    private let audioViewModel: AudioViewModel

    /// Where the EQ persists (`+Persistence`): the launch's `AppDataLocation.defaults`. The debug
    /// picture-sheet renderer injects its own suite so a render never reads or writes the user's EQ.
    let defaults: UserDefaults

    // MARK: - Compare, Bring back and the played curve (EQ3; none of it persisted)

    /// Compare is held: the song plays without the EQ until it is released (decision 28). Every change
    /// to what plays releases it (`setCurrent`).
    private(set) var isComparing = false

    /// Edits a preset switch set aside, offered back until the next edit (decision 27).
    private(set) var bringBack: EQBringBack?

    /// One design, kept with what it was designed for.
    private struct PlayedMemo {
        let points: [Float]
        let rate: Double
        let played: EQPlayed?
    }

    /// The played curve's memo: the points and design rate it was designed for (`played`).
    @ObservationIgnored private var playedMemo: PlayedMemo?

    /// This model's own designer (one per owner — the C-ABI's rule), made on the first `played` read.
    @ObservationIgnored private var designer: EQDesigner?

    // MARK: - Derived (never stored)

    /// What the current output plays: its pinned slot, else the shared one.
    var current: EQState {
        store[slot: store.slotID(for: output)]
    }

    /// The 31 points drawn and sent.
    var points: [Float] {
        current.points
    }

    /// Whether the current state differs from its preset (the "Edited" rule).
    var isEdited: Bool {
        current.isEdited(myPresets: customPresets)
    }

    /// The preset as it plays: "Warm", "Warm · edited", "Late Night".
    var presetLabel: String {
        let name = current.preset.displayName
        return isEdited ? "\(name) · edited" : name
    }

    /// One line for the EQ as it plays: `presetLabel`, or "Off".
    var summary: String {
        current.isOn ? presetLabel : "Off"
    }

    /// What the listener hears from the EQ now: the graph's look, its strip and Compare follow it.
    var audible: EQAudibleState {
        EQAudibleState(isOn: current.isOn, isComparing: isComparing,
                       pureModeEngaged: audioViewModel.pureModeEngaged, engineReady: audioViewModel.isEngineReady)
    }

    /// The curve the EQ plays for `points` at the engine's design rate, from EQ1a's designer: designed
    /// on first read (only while the graph shows) and memoized on both, so a redraw that changes neither
    /// never designs again. `nil` only if the designer rejects the input.
    var played: EQPlayed? {
        let drawn = points
        let rate = audioViewModel.eqSampleRate()
        if let playedMemo, playedMemo.points == drawn, playedMemo.rate == rate {
            return playedMemo.played
        }
        let owned = designer ?? EQDesigner()
        designer = owned
        let design = owned.played(points: drawn, sampleRate: rate)
        playedMemo = PlayedMemo(points: drawn, rate: rate, played: design)
        return design
    }

    init(audioViewModel: AudioViewModel, defaults: UserDefaults) {
        self.audioViewModel = audioViewModel
        self.defaults = defaults
        let myPresets = Self.loadMyPresets(from: defaults)
        customPresets = myPresets
        store = Self.loadStore(from: defaults, myPresets: myPresets)
        // Headless re-send: `publish()` no-ops until the engine is up, so this hook sends the restored
        // EQ the moment it is — with the EQ tab closed too. A lifecycle hook, not a device recall.
        audioViewModel.onEngineReady = { [weak self] in self?.publish() }
        publish()
    }

    // MARK: - Presets

    /// Choose a preset: its points, Tone at 0, and the EQ on. Re-choosing the current preset resets
    /// it. A My Preset that no longer exists is ignored.
    func choose(_ preset: EQPresetRef) {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        guard let state = EQState(choosing: preset, myPresets: customPresets) else { return }
        bringBack = EQBringBack.afterSwitch(from: bringBack, leaving: current, to: preset, myPresets: customPresets)
        logUX("EQ preset → '\(preset.displayName)'")
        setCurrent(state)
        persist()
    }

    // MARK: - Outputs

    /// The sound moved to another output (Edge 5; fired only when the UID changes). Its slot — its
    /// pin, else shared — becomes current, and a drag in progress stays with the slot it was made
    /// on. When that changes what plays, it is sent, and the toast names the output and its EQ —
    /// except for the launch's first output (after a gap with no output, the next one toasts: E2).
    func outputDidChange(to key: EQOutputKey?) {
        endStroke(beforeMovingTo: key)
        endCompare() // a held Compare never carries over to another output (decision 28)
        bringBack = nil // edits set aside belong to the output they were made on
        let before = current
        let hadSeenOutput = hasSeenOutput
        hasSeenOutput = hasSeenOutput || key != nil
        output = key
        logUX("EQ output → '\(key?.name ?? "none")' slot=\(store.slotID(for: key) ?? "shared")")
        guard current != before else { return }
        publish()
        if hadSeenOutput, let key {
            outputToast.show("\(key.name) · \(summary)")
        }
    }

    // MARK: - Writing and sending

    /// An edit: the current slot plays `curve` from now on, and the EQ turns on.
    func edit(to curve: EQCurve) {
        if bringBack != nil {
            bringBack = nil // a new edit: the edits set aside are no longer offered back (decision 27)
        }
        var state = current
        state.edit(to: curve)
        setCurrent(state)
    }

    /// Writes `state` into the current output's slot and sends it: the path every change takes.
    func setCurrent(_ state: EQState) {
        if isComparing {
            isComparing = false // any change to what plays releases a held Compare (decision 28)
        }
        store[slot: store.slotID(for: output)] = state
        publish()
    }

    /// THE dispatch (the contract's one send): what the current slot plays. A no-op until the engine
    /// is up (`onEngineReady` re-sends). The engine validates and coalesces, so a drag sends every
    /// pointer sample.
    private func publish() {
        guard audioViewModel.isEngineReady else { return }
        audioViewModel.publishEQ(points: current.points, isOn: current.isOn && !isComparing)
    }

    // MARK: - Compare and Bring back (EQ3)

    /// Compare pressed (decision 28): the song plays without the EQ, at matched loudness, until
    /// `endCompare`. Only while the EQ really plays (`EQAudibleState.canCompare`).
    func beginCompare() {
        guard !isComparing, audible.canCompare else { return }
        isComparing = true
        publish()
        logUX("EQ compare → held")
    }

    /// Compare released: the EQ plays again. Safe to call any time — every release path (Esc, focus
    /// loss, a tab change, an output change) calls it.
    func endCompare() {
        guard isComparing else { return }
        isComparing = false
        publish()
        logUX("EQ compare → released")
    }

    /// Bring back the edits a preset switch set aside: the whole slot as it was (preset, base, Tone and
    /// On/Off). The offer is then gone.
    func bringBackEdits() {
        guard let bringBack else { return }
        endStroke() // a discrete edit ends a drag first (+Stroke)
        self.bringBack = nil
        setCurrent(bringBack.edits)
        persist()
        logUX("EQ bring back edits → '\(presetLabel)'")
    }
}

// MARK: - My Presets and the pin (EQ4)

/// Save, rename and delete (the kit's `EQMyPresets`, names checked by `EQPresetName`) and the "Used on
/// <output>" pin (`EQStore.pin` / `unpin`, decision 28). Each changes the slots and My Presets together,
/// so it lives beside the state it writes; each ends a drag first, persists what it changed, and sends
/// what plays — a change to what plays releases a held Compare, like every edit.
extension EQViewModel {
    /// How the current output stands with the pins; `nil` with no output, or one that can't be pinned.
    var outputPin: EQOutputPin? {
        store.pin(for: output)
    }

    /// What Save would save now: taken when the Save sheet opens (break-it C1).
    func saveSource() -> EQSaveSource {
        store.saveSource(for: output)
    }

    /// `typed` checked as a My Preset's name, for the sheet's inline copy (`renaming` one of them).
    func nameCheck(_ typed: String, renaming: String? = nil) -> EQPresetName.Check {
        EQPresetName.check(typed, among: customPresets.keys, renaming: renaming)
    }

    /// Save `source` as the My Preset `typed` names (replacing one of that name), the Tone baked in: the
    /// slot it came from plays it, unedited — even after the output switched while the sheet was open.
    func save(_ source: EQSaveSource, as typed: String) {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        var saved: String?
        changeSlots { store, myPresets in
            saved = EQMyPresets.save(source, as: typed, store: &store, myPresets: &myPresets)
        }
        guard let saved else { return }
        bringBack = nil // Save keeps what plays; edits set aside earlier are no longer offered
        persistMyPresets()
        persist()
        logUX("EQ save preset '\(saved)'")
    }

    /// Rename the My Preset `name` to what `typed` names; every slot playing it, and edits set aside on
    /// it, follow.
    func renameMyPreset(_ name: String, to typed: String) {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        var renamed: String?
        changeSlots { store, myPresets in
            renamed = EQMyPresets.rename(name, to: typed, store: &store, myPresets: &myPresets)
        }
        guard let renamed, renamed != name else { return }
        bringBack = bringBack?.repointingMyPresets { $0 == name ? renamed : $0 }
        persistMyPresets()
        persist()
        logUX("EQ rename preset '\(name)' → '\(renamed)'")
    }

    /// Delete the My Preset `name`. Whatever plays it keeps its sound, as an edited Flat.
    func deleteMyPreset(_ name: String) {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        guard customPresets[name] != nil else { return }
        changeSlots { store, myPresets in
            EQMyPresets.delete(name, store: &store, myPresets: &myPresets)
        }
        bringBack = bringBack?.repointingMyPresets { $0 == name ? nil : $0 }
        persistMyPresets()
        persist()
        logUX("EQ delete preset '\(name)'")
    }

    /// The "Used on <output>" pin, pressed: pin the current output (it keeps exactly what plays now, and
    /// its edits from then on), or unpin the pin it plays (the shared slot takes it over, so nothing
    /// audible changes). Nothing for an output that can't be pinned.
    func togglePin() {
        guard let pin = outputPin else { return }
        endStroke() // a discrete edit ends a drag first (+Stroke)
        changeSlots { store, _ in
            if pin.isPinned {
                store.unpin(pin.output)
            } else {
                store.pin(pin.output)
            }
        }
        persist()
        logUX("EQ \(pin.isPinned ? "unpin" : "pin") → '\(pin.output.name)'")
    }

    /// The one write of the slots and My Presets together, then the one send. Only a change to what
    /// plays releases a held Compare (pinning and unpinning keep the sound).
    private func changeSlots(_ change: (inout EQStore, inout [String: [Float]]) -> Void) {
        let before = current
        change(&store, &customPresets)
        if current != before, isComparing {
            isComparing = false
        }
        publish()
    }
}

#if DEBUG
    extension EQViewModel {
        /// Picture sheets: every output plays `state`, with `myPresets` saved (neither persisted nor sent).
        func seedRenderFixture(state: EQState, myPresets: [String: [Float]]) {
            customPresets = myPresets
            store = EQStore(shared: state)
        }
    }
#endif
