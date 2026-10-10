import EQEditKit
import Foundation

// MARK: - EQViewModel

/// The EQ the user edits and hears (the Sprint EQ contract, review §2). It holds one `EQStore` of
/// slots — `shared` for every unpinned output, one per pinned output — and the CURRENT output's
/// slot is `current`. Every editing rule lives in `EQEditKit`; this owns the state, sends it to the
/// engine from ONE place (`publish()`), and persists it (`+Persistence`).
///
/// - Edits: choosing a preset and Save here; the drag and the keyboard step in `+Stroke`. Every edit
///   goes through `edit(to:)` or `setCurrent(_:)`, and every edit turns the EQ on.
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

    /// The output-switch toast, shown by `EQOutputToast` in the shell overlay for 3 s (UI plan §4.4).
    let outputToast = ShellToastSlot(lifetime: .seconds(3))

    /// The drag in progress (`+Stroke`); internal so that extension can drive it. Never observed.
    @ObservationIgnored var stroke: ActiveStroke?

    private let audioViewModel: AudioViewModel

    /// Where the EQ persists (`+Persistence`): the launch's `AppDataLocation.defaults`. The debug
    /// picture-sheet renderer injects its own suite so a render never reads or writes the user's EQ.
    let defaults: UserDefaults

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
        logUX("EQ preset → '\(preset.displayName)'")
        setCurrent(state)
        persist()
    }

    /// Save what plays as the My Preset `name` (replacing one of that name), Tone baked in. The
    /// current slot then plays that preset, unedited.
    func save(as name: String) {
        endStroke() // a discrete edit ends a drag first (+Stroke)
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let saved = current.saved(as: name)
        customPresets[name] = saved.points
        persistMyPresets()
        setCurrent(saved)
        persist()
        logUX("EQ save preset '\(name)'")
    }

    // MARK: - Outputs

    /// The sound moved to another output (Edge 5; fired only when the UID changes). Its slot — its
    /// pin, else shared — becomes current, and a drag in progress stays with the slot it was made
    /// on. When that changes what plays, it is sent, and the toast names the output and its EQ —
    /// except at launch, when no output played before.
    func outputDidChange(to key: EQOutputKey?) {
        endStroke(beforeMovingTo: key)
        let before = current
        let hadOutput = output != nil
        output = key
        logUX("EQ output → '\(key?.name ?? "none")' slot=\(store.slotID(for: key) ?? "shared")")
        guard current != before else { return }
        publish()
        if hadOutput, let key {
            outputToast.show("\(key.name) · \(summary)")
        }
    }

    // MARK: - Writing and sending

    /// An edit: the current slot plays `curve` from now on, and the EQ turns on.
    func edit(to curve: EQCurve) {
        var state = current
        state.edit(to: curve)
        setCurrent(state)
    }

    /// Writes `state` into the current output's slot and sends it: the path every change takes.
    func setCurrent(_ state: EQState) {
        store[slot: store.slotID(for: output)] = state
        publish()
    }

    /// THE dispatch (the contract's one send): what the current slot plays. A no-op until the engine
    /// is up (`onEngineReady` re-sends). The engine validates and coalesces, so a drag sends every
    /// pointer sample.
    private func publish() {
        guard audioViewModel.isEngineReady else { return }
        audioViewModel.publishEQ(points: current.points, isOn: current.isOn)
    }
}

#if DEBUG
    extension EQViewModel {
        /// Picture sheets: every output plays `points` as an edited Flat (neither persisted nor sent).
        func seedRenderFixture(points: [Float]) {
            var state = EQState.flat
            state.edit(to: EQCurve(points: points))
            store = EQStore(shared: state)
        }
    }
#endif
