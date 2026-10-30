import AudioDSP
import Foundation
import LevelingKit
import Synchronization

// MARK: - AudioEngineBridge leveling (R1.1-B, the level-and-fold design §1.3 and §S3)

//
// Lane 1's file in W4 (docs/design/level-and-fold/README.md §9, condition C3.3). The bridge's stored `leveling`
// property (AudioEngineBridge.swift, the coordinator's line) is of this file's type.
//
// THE FLOW. Every request that can make a track audible carries its decision (`startAudio(…, leveling:)`,
// `setNextTrack(…, leveling:)`, B2); the bridge keeps it beside the request until the track becomes audible, then
// plans ONCE (`asPlanTrack`, B1) against the one output state, and hands the same plan to both units in the same
// turn: the effects unit (the leveling gain under the cap) and the spatial unit (the fold's trim and LFE gain,
// lane 2's — `setFoldPlanSink`). When the decision carries the track's saved −ΔL profile (C2), it reaches the
// effects unit first, so a fresh start of an analysed track never glides. A listener's mode change re-plans the
// audible track and replaces the armed decision (N11); an output change re-plans protectively with the gain
// frozen (F5). A start says whether it resumes the listen that was playing (Pause → Play) or begins a new one
// (`LevelingStart`): a resume of the audible track keeps its plan — the level never steps inside a song — and a new
// play is planned afresh, the same file too. A seek or a device move re-schedules the track without a start and
// sends nothing (B1).
//
// THE OUTPUT STATE (M2) is assembled by lane 2 on `engineQueue` — at `configureGraphForSource` and at every
// re-establish — and handed here (`applyOutputState`); its `transportType` is the view model's hand-over
// (`publishOutputTransport`, a value, never read on main), which lane 2 reads back with `levelingOutputTransport()`.
//
// THREADS. A track becomes audible on `engineQueue` (a start) or on `resampleQueue` (a gapless seam), a mode change
// arrives from the main thread, the output state from `engineQueue`: so the state is guarded by its own lock,
// held only to read, plan and hand the plan on (no hardware call, no wait). NEVER call into it while holding the
// bridge's `stateLock` (the effects unit's borrow takes that lock inside this one).

/// What the bridge keeps for leveling between a start or arm and the moment its track becomes audible — the
/// decision each request carries, the output state — and what the planner made of them; and the planning itself,
/// so one lock covers the plan and both units' deliveries. Any thread.
final class EngineLevelingState: Sendable {
    /// The fold's half of a plan, delivered by the spatial unit's owner (lane 2), with why it came — a fresh start
    /// snaps, a gapless seam glides 10 ms, a mode change 0.15 s, an output change is the protective re-plan — so the
    /// fold moves exactly as the effects unit does (NI-4).
    typealias FoldPlanSink = @Sendable (AsTrackPlan, AsOutputState, AsPlanEvent) -> Void

    /// One plan for the effects unit: its track, why it comes, the plan, the continuity verdict, and the saved
    /// profile to publish first (C2).
    struct Delivery {
        let token: UInt64
        let event: AsPlanEvent
        let plan: AsTrackPlan
        let continuous: Bool
        let saved: SavedLoudnessProfile?
    }

    /// The effects unit's half of a delivery (the bridge's borrow and C-ABI): the address of the AU it reached,
    /// nil when no AU is live.
    typealias EffectsDelivery = (Delivery) -> UInt?

    /// A request's decision, waiting for its track to become audible, with its saved profiles rebuilt (off any
    /// seam), and whether the request resumes the listen that was playing (a start's `LevelingStart.Listen`; an
    /// arm never does).
    struct Pending: Sendable {
        let url: URL
        let decision: TrackLevelingDecision
        let saved: [SavedLoudnessProfile]
        let resumes: Bool

        /// `decision`'s, its saved profiles rebuilt for the engine (the ones that can be): binary16 → float, so
        /// never on the main thread or at a seam.
        init(url: URL, decision: TrackLevelingDecision, resumes: Bool = false) {
            self.init(url: url, decision: decision, saved: decision.profiles.compactMap { SavedLoudnessProfile($0) },
                      resumes: resumes)
        }

        init(url: URL, decision: TrackLevelingDecision, saved: [SavedLoudnessProfile], resumes: Bool) {
            self.url = url
            self.decision = decision
            self.saved = saved
            self.resumes = resumes
        }
    }

    /// The audible track: its file, its decision, its plan and the output it was planned against, the effects unit
    /// that has it, and its saved profile in force.
    private struct Audible: Sendable {
        let token: UInt64
        let url: URL
        var decision: TrackLevelingDecision?
        var plan: AsTrackPlan
        var plannedFor: AsOutputState
        var deliveredTo: UInt? // the effects AU's address its play reached (B1 holds per unit)
        var savedProfile: SavedLoudnessProfile?
    }

    private struct Held: Sendable {
        var output = AsOutputState.unknownStereo
        var foldPlanSink: FoldPlanSink?
        var start: Pending?
        var armed: Pending?
        var audible: Audible?
    }

    private let held = Mutex(Held())

    /// The output's transport as the view model handed it over (0 = not yet).
    var outputTransport: UInt32 {
        held.withLock { $0.output.transportType }
    }

    /// The output state the planner plans against.
    var outputState: AsOutputState {
        held.withLock { $0.output }
    }

    /// Diagnostics and tests: the audible track's plan, if any.
    var audiblePlan: AsTrackPlan? {
        held.withLock { $0.audible?.plan }
    }

    func setFoldPlanSink(_ sink: FoldPlanSink?) {
        held.withLock { $0.foldPlanSink = sink }
    }

    /// A start's decision (`nil`: none — a Pure start), kept for its track's audibility.
    func holdStart(_ pending: Pending?) {
        held.withLock { $0.start = pending }
    }

    /// The pick armed for the gapless seam and its decision (`nil`: cleared, or a pick without one).
    func arm(_ pending: Pending?) {
        held.withLock { $0.armed = pending }
    }

    /// `url` (token `token`) became audible: plan once and hand the plan to both units (B1). A start that resumes
    /// the audible track goes on with its plan (`resume`); any other start, and every seam, is a new play, planned
    /// afresh — the same file too. Returns whether the track's saved profile is in force (C2).
    func becameAudible(_ url: URL, token: UInt64, gaplessSeam: Bool, unit: UInt?,
                       effects: EffectsDelivery) -> Bool {
        held.withLock { held -> Bool in
            let matched = Self.takeRequest(for: url, gaplessSeam: gaplessSeam, held: &held)
            // Token 0 (the file's attributes unreadable) names no track: never "the same one" (N2).
            if let matched, matched.resumes, let audible = held.audible, audible.token == token, token != 0 {
                return Self.resume(audible, url: url, unit: unit, held: &held, effects: effects)
            }
            if matched == nil {
                logUX("leveling: no decision as '\(url.lastPathComponent)' became audible — Off, the fold's "
                    + "worst-case trim (a bug: every start and arm carries one)")
            }
            let plan = Self.plan(matched?.decision, output: held.output, frozen: nil)
            let profile = matched?.saved.first { $0.basis == Self.basis(of: plan) }
            let event = gaplessSeam ? AsPlanEventGaplessSeam : AsPlanEventFreshStart
            let delivered = Self.deliver(.init(token: token, event: event, plan: plan,
                                               continuous: matched?.decision.continuousWithPrevious ?? false,
                                               saved: profile),
                                         held: held, effects: effects)
            held.audible = Audible(token: token, url: url, decision: matched?.decision, plan: plan,
                                   plannedFor: held.output, deliveredTo: delivered, savedProfile: profile)
            logUX("leveling: '\(url.lastPathComponent)' audible (\(gaplessSeam ? "gapless seam" : "fresh start")) — "
                + Self.describe(plan) + (profile != nil ? ", saved profile" : ""))
            return profile != nil
        }
    }

    /// The listener changed the mode (R1.1-B, review S2): each decision goes to the song it names, wherever it is now.
    /// `current` re-plans the audible track (0.15 s glide), or replaces a start's decision not yet audible; `next`
    /// replaces the armed pick's (N11), or — when a seam has already made that pick audible — re-plans it. One that
    /// names a song this state no longer has is dropped: the caller re-sends once its requests have landed.
    func changeMode(current: Pending?, next: Pending?, effects: EffectsDelivery) {
        held.withLock { held in
            var replan: Pending?
            if let current {
                if held.audible?.url == current.url {
                    replan = current
                } else if let start = held.start, start.url == current.url {
                    held.start = Pending(url: start.url, decision: current.decision, saved: current.saved,
                                         resumes: start.resumes)
                } else {
                    logUX("leveling: a mode change for '\(current.url.lastPathComponent)', no longer playing — dropped")
                }
            }
            if let next {
                if held.armed?.url == next.url {
                    held.armed = next
                } else if held.audible?.url == next.url {
                    replan = next // the seam has already made the armed pick audible
                } else {
                    logUX("leveling: a mode change for '\(next.url.lastPathComponent)', not armed — dropped")
                }
            }
            if let replan {
                Self.replanForMode(replan, held: &held, effects: effects)
            }
        }
    }

    /// The output state changed: plan against it from now on, and re-plan the audible track protectively (F5).
    func changeOutput(_ state: AsOutputState, effects: EffectsDelivery) {
        held.withLock { held in
            guard !held.output.isSame(as: state) else { return }
            held.output = state
            Self.replanForOutput(&held, effects: effects)
        }
    }

    /// The view model handed over a new transport: the output state follows (F5 as for any output change).
    func changeTransport(_ transportType: UInt32, effects: EffectsDelivery) {
        held.withLock { held in
            guard held.output.transportType != transportType else { return }
            held.output.transportType = transportType
            Self.replanForOutput(&held, effects: effects)
        }
    }

    // MARK: Private (inside the lock)

    /// The request `url` plays, taken from where it waits. A seam plays the armed pick. A fresh start plays its own
    /// request — or, when that is not this URL, the armed pick started fresh (a gapless roll that could not join
    /// restarts it through playFile).
    private static func takeRequest(for url: URL, gaplessSeam: Bool, held: inout Held) -> Pending? {
        if gaplessSeam {
            defer { held.armed = nil }
            return (held.armed?.url == url) ? held.armed : nil
        }
        defer { held.start = nil }
        if held.start?.url == url {
            return held.start
        }
        guard held.armed?.url == url else { return nil }
        defer { held.armed = nil }
        return held.armed
    }

    /// A start resumed the audible track `url` (B2): the same listen goes on at the level it plays at, so its plan
    /// stays, whatever decision the resume carries. The graph's configure has just set the fold back to the
    /// layout's (its worst-case trim), so the fold gets the plan's half again — snapped, as the stream starts
    /// again. An output that changed meanwhile re-plans protectively first (F5); another effects unit (an engine
    /// rebuilt) gets the whole plan. Returns whether the track's saved profile is in force.
    private static func resume(_ audible: Audible, url: URL, unit: UInt?, held: inout Held,
                               effects: EffectsDelivery) -> Bool {
        var audible = audible
        let outputChanged = !audible.plannedFor.isSame(as: held.output)
        if outputChanged {
            audible.plan = plan(audible.decision, output: held.output, frozen: audible.plan)
            audible.plannedFor = held.output
        }
        if let unit, audible.deliveredTo == unit {
            if outputChanged {
                _ = effects(.init(token: audible.token, event: AsPlanEventOutputChange, plan: audible.plan,
                                  continuous: false, saved: nil))
            }
            held.foldPlanSink?(audible.plan, held.output, AsPlanEventFreshStart)
        } else {
            audible.deliveredTo = deliver(.init(token: audible.token, event: AsPlanEventFreshStart, plan: audible.plan,
                                                continuous: false, saved: audible.savedProfile),
                                          held: held, effects: effects)
        }
        held.audible = audible
        logUX("leveling: '\(url.lastPathComponent)' resumed — its plan stays: " + describe(audible.plan))
        return audible.savedProfile != nil
    }

    /// The audible track re-plans from the listener's new mode (0.15 s glide, both units alike). A plan on another
    /// basis than the saved profile in force sends the new basis's first (S3), as a play would choose it.
    private static func replanForMode(_ request: Pending, held: inout Held, effects: EffectsDelivery) {
        guard var audible = held.audible else { return }
        audible.decision = request.decision
        audible.plan = plan(request.decision, output: held.output, frozen: nil)
        audible.plannedFor = held.output
        let basis = basis(of: audible.plan)
        let resent = audible.savedProfile?.basis == basis ? nil : request.saved.first { $0.basis == basis }
        _ = deliver(.init(token: audible.token, event: AsPlanEventModeChange, plan: audible.plan, continuous: false,
                          saved: resent),
                    held: held, effects: effects)
        audible.savedProfile = resent ?? audible.savedProfile
        held.audible = audible
        logUX("leveling: the mode changed — '\(audible.url.lastPathComponent)' re-planned: " + describe(audible.plan)
            + (resent != nil ? ", its saved profile on the new basis" : ""))
    }

    /// The −ΔL basis `plan` plays on: the fold at its LFE variant, or as decoded.
    private static func basis(of plan: AsTrackPlan) -> CompactLoudnessProfile.Basis {
        plan.folds != 0 ? .fold(lfeVariant: Int(plan.lfeVariant)) : .decoded
    }

    /// The protective re-plan of the audible track against the output now held (F5): g and the LFE variant frozen.
    /// The unit that has the track's play keeps it (N3: an output change is not a play).
    private static func replanForOutput(_ held: inout Held, effects: EffectsDelivery) {
        guard var audible = held.audible else { return }
        audible.plan = plan(audible.decision, output: held.output, frozen: audible.plan)
        audible.plannedFor = held.output
        _ = deliver(.init(token: audible.token, event: AsPlanEventOutputChange, plan: audible.plan, continuous: false,
                          saved: nil),
                    held: held, effects: effects)
        held.audible = audible
        logUX("leveling: the output changed — re-planned protectively: " + describe(audible.plan))
    }

    /// One delivery, both units in the same turn: the effects unit (its saved profile first), then the fold.
    private static func deliver(_ delivery: Delivery, held: Held, effects: EffectsDelivery) -> UInt? {
        let unit = effects(delivery)
        held.foldPlanSink?(delivery.plan, held.output, delivery.event)
        return unit
    }

    /// The planner's plan for `decision` (none: Off, the fold's worst-case trim) on `output`; `frozen`: the playing
    /// plan, for the protective re-plan.
    private static func plan(_ decision: TrackLevelingDecision?, output: AsOutputState,
                             frozen: AsTrackPlan?) -> AsTrackPlan {
        var output = output
        return withOptionalPointer(to: decision.map(AsTrackLeveling.init)) { mirror in
            withOptionalPointer(to: frozen) { asPlanTrack(mirror, &output, $0) }
        }
    }

    /// `body` with a pointer to `value`, or nil (the C-ABI's "none").
    private static func withOptionalPointer<Value, Result>(to value: Value?,
                                                           _ body: (UnsafePointer<Value>?) -> Result) -> Result {
        guard let value else { return body(nil) }
        return withUnsafePointer(to: value) { body($0) }
    }

    private static func describe(_ plan: AsTrackPlan) -> String {
        let mode = switch Int(plan.mode) {
        case Int(AsLevelingModeLeveled.rawValue): "leveled"
        case Int(AsLevelingModeUnknownCut.rawValue): "unknown loudness"
        default: "Off"
        }
        let fold = plan.folds != 0 ? String(format: ", folded (trim %+.2f dB)", plan.foldTrimDb) : ""
        return mode + String(format: ", g %+.2f dB, P %+.2f dBTP, C_work %+.3f dBTP", plan.levelGainDb,
                             plan.peakDbtp, plan.workingCeilingDbtp) + fold
    }
}

/// Caseless-enum namespace holding the effects unit's leveling C-ABI, so the extension's own methods never shadow
/// the free functions (the `CIntensityABI` pattern). Immutable C-function pointers.
private enum CLevelingABI {
    static let plan: @Sendable (UnsafeMutableRawPointer?, UInt64, UInt8, UnsafePointer<AsTrackPlan>?, Bool) -> Void =
        applyTrackPlan
    static let saved: @Sendable (UnsafeMutableRawPointer?, UInt64, OpaquePointer?) -> Bool =
        publishSavedLoudnessProfile
}

extension AudioEngineBridge {
    // MARK: The seams lane 2 calls (the output state, the fold)

    /// The output's transport as the view model last handed it over (0 = unknown): the `transportType` of the
    /// output state lane 2 assembles. Any thread.
    func levelingOutputTransport() -> UInt32 {
        leveling.outputTransport
    }

    /// The output state changed (lane 2: on `engineQueue`, at `configureGraphForSource` and at every
    /// re-establish, with `transportType` from `levelingOutputTransport()`). The planner plans against it from now
    /// on; a change while a track plays re-plans that track protectively, its leveling gain frozen (F5). Never call
    /// it while holding `stateLock`.
    func applyOutputState(_ state: AsOutputState) {
        leveling.changeOutput(state, effects: deliverToEffects)
    }

    /// Where the fold's half of every plan goes (lane 2: once, where the spatial unit attaches; `nil` to detach),
    /// with the plan's event. The sink runs inside the leveling lock, in the same turn the effects unit gets the
    /// same plan and event, so it must only hand the plan on (the spatial unit's snapshot) — never wait, never take
    /// `stateLock` for longer than a borrow.
    func setFoldPlanSink(_ sink: EngineLevelingState.FoldPlanSink?) {
        leveling.setFoldPlanSink(sink)
    }

    // MARK: AudioPlaybackEngine

    /// The listener changed the Leveling mode (`AudioPlaybackEngine.applyLevelingChange`): each decision goes to the
    /// song it names (`EngineLevelingState.changeMode`). Off the main thread: the decisions' saved profiles are
    /// rebuilt on `engineQueue` (binary16 → float, N14) — after every start already there — and applied on
    /// `resampleQueue`, after every arm already admitted (the on-deck slot is set there). Returns once applied.
    func applyLevelingChange(current: SongLeveling?, next: SongLeveling?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engineQueue.async {
                let current = current.map { EngineLevelingState.Pending(url: $0.url, decision: $0.decision) }
                let next = next.map { EngineLevelingState.Pending(url: $0.url, decision: $0.decision) }
                self.resampleQueue.async {
                    self.leveling.changeMode(current: current, next: next, effects: self.deliverToEffects)
                    continuation.resume()
                }
            }
        }
    }

    // MARK: The requests and audibility (+Playback, +Gapless, +TrackLoudness)

    /// A start's decision and listen, kept for its track's audibility (`engineQueue`, before `playFile`). A Pure
    /// start keeps none: leveling in Pure is deferred (record decision 1).
    func holdStartDecision(_ start: LevelingStart?, for url: URL) {
        leveling.holdStart(start.map {
            EngineLevelingState.Pending(url: url, decision: $0.decision, resumes: $0.listen == .resume)
        })
    }

    /// The pick armed for the gapless seam, with its decision (`resampleQueue`, beside `onDeckURL`, so the seam reads
    /// the decision of the URL it plays). `nil` clears it. Build the pending decision off the seam
    /// (`EngineLevelingState.Pending(url:decision:)` rebuilds the saved profiles).
    func armLeveling(_ pending: EngineLevelingState.Pending?) {
        leveling.arm(pending)
    }

    /// `url` (token `token`) became audible: plan once, both units in one turn (B1). Returns whether the track's
    /// saved profile went with it (then the analyzer has nothing to do: the saved profile is final, C2).
    func planAudible(_ url: URL, token: UInt64, gaplessSeam: Bool) -> Bool {
        let unit = withEffectsAU { UInt(bitPattern: $0) }
        return leveling.becameAudible(url, token: token, gaplessSeam: gaplessSeam, unit: unit,
                                      effects: deliverToEffects)
    }

    /// The view model handed over a new transport: the output state follows, and the audible track re-plans
    /// protectively (F5). Any thread (the main thread's `publishOutputTransport`).
    func levelingTransportChanged(_ transportType: UInt32) {
        leveling.changeTransport(transportType, effects: deliverToEffects)
    }

    /// The effects unit's half of a delivery: the saved profile first (C2), then the plan — two posts to its
    /// Realizer's queue, in order. Returns the AU's address (nil when it isn't live).
    private func deliverToEffects(_ delivery: EngineLevelingState.Delivery) -> UInt? {
        var plan = delivery.plan
        return withEffectsAU { handle -> UInt in
            if let saved = delivery.saved {
                _ = CLevelingABI.saved(handle, delivery.token, saved.pointer)
            }
            CLevelingABI.plan(handle, delivery.token, UInt8(delivery.event.rawValue), &plan, delivery.continuous)
            return UInt(bitPattern: handle)
        }
    }
}
