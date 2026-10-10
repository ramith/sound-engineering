import EQEditKit
import Foundation

// MARK: - EQViewModel

/// The EQ the user edits and hears (the Sprint EQ contract, review §2), as the app sees it. Every
/// decision is `EQSession`'s (the kit, under test): the slots, My Presets, the output, a drag, a held
/// Compare and the Bring back offer, and what each verb does to them. This owns the session and carries
/// out what a verb asks (`EQOutcome`): the ONE send to the engine (`publish()`), the writes
/// (`+Persistence`), the UX log and the output toast. It adds only what is the app's: the played curve
/// (EQ1a's designer, at the engine's observed design rate) and the Tone region the screen is on.
///
/// - Verbs: `+Verbs`, one line each over the session.
/// - Outputs: `outputDidChange(to:)`, wired at the composition root (Edge 5), makes the new output's
///   slot current — with the window closed too — and raises `outputToast` when the sound changed.
@MainActor
@Observable
final class EQViewModel {
    // MARK: - State

    /// The EQ and every rule about it.
    private(set) var session: EQSession

    /// The output-switch toast, shown by `EQOutputToast` in the shell overlay for 3 s (UI plan §4.4).
    let outputToast = ShellToastSlot(lifetime: .seconds(3))

    /// The Tone region the user is on — a Tone slider hovered, dragged or keyboard-focused
    /// (`EQToneCard`, the one writer) — which the graph shades, with its readout. View state: never
    /// persisted, and `nil` while no Tone slider is in use.
    var highlightedRegion: EQToneRegion?

    private let audioViewModel: AudioViewModel

    /// Where the EQ persists (`+Persistence`): the launch's `AppDataLocation.defaults`. The debug
    /// picture-sheet renderer injects its own suite so a render never reads or writes the user's EQ.
    let defaults: UserDefaults

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

    /// Every slot the EQ remembers, persisted whole as `eqStateV2`.
    var store: EQStore {
        session.store
    }

    /// The user's saved presets (My Presets), name → points; persisted as `eqCustomPresetsV1`.
    var customPresets: [String: [Float]] {
        session.myPresets
    }

    /// What the current output plays: its pinned slot, else the shared one.
    var current: EQState {
        session.current
    }

    /// What the listener hears from the EQ now: the graph's look, its strip and Compare follow it.
    var audible: EQAudibleState {
        EQAudibleState(isOn: current.isOn, isComparing: session.isComparing,
                       pureModeEngaged: audioViewModel.pureModeEngaged, engineReady: audioViewModel.isEngineReady)
    }

    /// The curve the EQ plays for the points at the engine's design rate, from EQ1a's designer: designed
    /// on first read (only while the graph shows) and memoized on both. The rate is observed
    /// (`AudioViewModel.eqDesignRate`), so the graph redraws when the output's rate moves the design.
    /// `nil` only if the designer rejects the input.
    var played: EQPlayed? {
        let drawn = session.points
        let rate = audioViewModel.eqDesignRate
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
        session = EQSession(store: Self.loadStore(from: defaults, myPresets: myPresets), myPresets: myPresets)
        // Headless re-send: `publish()` no-ops until the engine is up, so this hook sends the restored
        // EQ the moment it is — with the EQ tab closed too. A lifecycle hook, not a device recall.
        audioViewModel.onEngineReady = { [weak self] in self?.publish() }
        publish()
    }

    // MARK: - Carrying out a verb

    /// Runs `verb` on the session and carries out what it asks: the send, the writes, the log lines and
    /// the toast. Returns the outcome, for the callers that branch on whether anything happened.
    @discardableResult
    func perform(_ verb: (inout EQSession) -> EQOutcome) -> EQOutcome {
        let outcome = verb(&session)
        if outcome.effects.contains(.send) {
            publish()
        }
        if outcome.effects.contains(.saveSlots) {
            persist()
        }
        if outcome.effects.contains(.saveMyPresets) {
            persistMyPresets()
        }
        outcome.log.forEach { logUX($0) }
        if let toast = outcome.toast {
            outputToast.show(toast)
        }
        return outcome
    }

    /// The sound moved to another output (Edge 5; fired only when the UID changes, `nil` when none is
    /// left). The session decides what it sends and whether it toasts (`EQOutputSwitch`).
    func outputDidChange(to key: EQOutputKey?) {
        perform { $0.outputDidChange(to: key) }
    }

    /// THE dispatch (the contract's one send): what the current slot plays. A no-op until the engine
    /// is up (`onEngineReady` re-sends). The engine validates and coalesces, so a drag sends every
    /// pointer sample.
    private func publish() {
        guard audioViewModel.isEngineReady else { return }
        audioViewModel.publishEQ(points: session.points, isOn: session.plays)
    }
}

#if DEBUG
    extension EQViewModel {
        /// Picture sheets: every output plays `state`, with `myPresets` saved (neither persisted nor sent).
        func seedRenderFixture(state: EQState, myPresets: [String: [Float]]) {
            session = EQSession(store: EQStore(shared: state), myPresets: myPresets, output: session.output)
        }
    }
#endif
