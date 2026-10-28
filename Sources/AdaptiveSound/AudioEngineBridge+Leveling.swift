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
// frozen (F5). A resume, a seek or a device move of the same track to the same unit sends nothing (B1).
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
    /// seam).
    struct Pending: Sendable {
        let url: URL
        let decision: TrackLevelingDecision
        let saved: [SavedLoudnessProfile]

        init(url: URL, decision: TrackLevelingDecision) {
            self.url = url
            self.decision = decision
            saved = Self.savedProfiles(of: decision)
        }

        /// `decision`'s saved profiles, rebuilt for the engine (the ones that can be).
        static func savedProfiles(of decision: TrackLevelingDecision) -> [SavedLoudnessProfile] {
            decision.profiles.compactMap { SavedLoudnessProfile($0) }
        }

        init(url: URL, decision: TrackLevelingDecision, saved: [SavedLoudnessProfile]) {
            self.url = url
            self.decision = decision
            self.saved = saved
        }
    }

    /// The audible track: its decision, its plan, the effects unit that has it and its saved profile.
    private struct Audible: Sendable {
        let token: UInt64
        var decision: TrackLevelingDecision?
        var plan: AsTrackPlan
        var deliveredTo: UInt? // the effects AU's address the plan reached (B1 holds per unit)
        let savedProfile: SavedLoudnessProfile?
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

    /// `url` (token `token`) became audible: plan once and hand the plan to both units (B1). A fresh start of the
    /// track the effects unit `unit` already has — a resume, a seek, a device move — sends nothing; the same track on
    /// a new unit (an engine rebuilt) gets its own plan again. Returns whether the track's saved profile went with it.
    func becameAudible(_ url: URL, token: UInt64, gaplessSeam: Bool, unit: UInt?,
                       effects: EffectsDelivery) -> Bool {
        held.withLock { held -> Bool in
            let pending = gaplessSeam ? held.armed : held.start
            let matched = (pending?.url == url) ? pending : nil
            if gaplessSeam {
                held.armed = nil
            } else {
                held.start = nil
            }
            if !gaplessSeam, var audible = held.audible, audible.token == token {
                if let unit, audible.deliveredTo == unit {
                    return audible.savedProfile != nil // B1: the same track on the same unit — nothing to send
                }
                audible.deliveredTo = Self.deliver(.init(token: token, event: AsPlanEventFreshStart, plan: audible.plan,
                                                         continuous: false, saved: audible.savedProfile),
                                                   held: held, effects: effects)
                held.audible = audible
                return audible.savedProfile != nil
            }
            if matched == nil {
                logUX("leveling: no decision as '\(url.lastPathComponent)' became audible — Off, the fold's "
                    + "worst-case trim (a bug: every start and arm carries one)")
            }
            let plan = Self.plan(matched?.decision, output: held.output, frozen: nil)
            let basis: CompactLoudnessProfile.Basis = plan.folds != 0 ? .fold(lfeVariant: Int(plan.lfeVariant))
                : .decoded
            let profile = matched?.saved.first { $0.basis == basis }
            let event = gaplessSeam ? AsPlanEventGaplessSeam : AsPlanEventFreshStart
            let delivered = Self.deliver(.init(token: token, event: event, plan: plan,
                                               continuous: matched?.decision.continuousWithPrevious ?? false,
                                               saved: profile),
                                         held: held, effects: effects)
            held.audible = Audible(token: token, decision: matched?.decision, plan: plan, deliveredTo: delivered,
                                   savedProfile: profile)
            logUX("leveling: '\(url.lastPathComponent)' audible (\(gaplessSeam ? "gapless seam" : "fresh start")) — "
                + Self.describe(plan) + (profile != nil ? ", saved profile" : ""))
            return profile != nil
        }
    }

    /// The listener changed the mode: the audible track re-plans from `current` (0.15 s glide); `next` replaces the
    /// armed pick's decision (N11), its saved profiles `nextSaved`.
    func changeMode(current: TrackLevelingDecision, next: TrackLevelingDecision?, nextSaved: [SavedLoudnessProfile],
                    effects: EffectsDelivery) {
        held.withLock { held in
            if var audible = held.audible {
                audible.decision = current
                audible.plan = Self.plan(current, output: held.output, frozen: nil)
                audible.deliveredTo = Self.deliver(.init(token: audible.token, event: AsPlanEventModeChange,
                                                         plan: audible.plan, continuous: false, saved: nil),
                                                   held: held, effects: effects)
                held.audible = audible
            }
            if let armed = held.armed, let next {
                held.armed = Pending(url: armed.url, decision: next, saved: nextSaved)
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

    /// The protective re-plan of the audible track against the output now held (F5): g and the LFE variant frozen.
    private static func replanForOutput(_ held: inout Held, effects: EffectsDelivery) {
        guard var audible = held.audible else { return }
        audible.plan = plan(audible.decision, output: held.output, frozen: audible.plan)
        audible.deliveredTo = deliver(.init(token: audible.token, event: AsPlanEventOutputChange, plan: audible.plan,
                                            continuous: false, saved: nil),
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

/// A saved compact −ΔL profile rebuilt for the engine (`asLoudnessProfileFromCompact`, C2): one owned reference,
/// released on deinit. Immutable; the C-ABI makes a profile safe to read from any thread.
final class SavedLoudnessProfile: @unchecked Sendable {
    // @unchecked: the pointer is immutable after init and the profile behind it immutable and documented
    // thread-safe for reads (TrackLoudnessBridge.h, THREADS).

    let basis: CompactLoudnessProfile.Basis
    let pointer: OpaquePointer

    /// The engine's profile of `compact`; nil when it cannot be rebuilt (another grid, a short payload).
    init?(_ compact: CompactLoudnessProfile) {
        var info = AsCompactProfileInfo()
        info.sampleRate = compact.sampleRate
        info.bandsPerOctave = UInt32(clamping: compact.bandsPerOctave)
        info.bandCount = UInt32(clamping: compact.bandCount)
        info.blockCount = UInt32(clamping: compact.blockCount)
        info.blockStrideHops = UInt32(clamping: compact.blockStrideHops)
        let made = compact.powers.withUnsafeBufferPointer { powers in
            asLoudnessProfileFromCompact(&info, powers.baseAddress, UInt32(clamping: powers.count))
        }
        guard let made else { return nil }
        basis = compact.basis
        pointer = made
    }

    deinit {
        asLoudnessProfileDestroy(pointer)
    }
}

extension AsOutputState {
    /// The output before the graph has said otherwise: the engine's 48 kHz, stereo in and out, transport unknown.
    static var unknownStereo: AsOutputState {
        var state = AsOutputState()
        state.engineRateHz = 48000
        state.sourceChannels = 2
        state.outputChannels = 2
        state.sourceRoles.0 = UInt8(AsChannelRoleL.rawValue)
        state.sourceRoles.1 = UInt8(AsChannelRoleR.rawValue)
        return state
    }

    /// The same output, field by field.
    func isSame(as other: AsOutputState) -> Bool {
        var (left, right) = (sourceRoles, other.sourceRoles)
        let rolesMatch = withUnsafeBytes(of: &left) { lhs in withUnsafeBytes(of: &right) { lhs.elementsEqual($0) } }
        return transportType == other.transportType && engineRateHz == other.engineRateHz
            && sourceChannels == other.sourceChannels && outputChannels == other.outputChannels && rolesMatch
    }
}

extension AsTrackLeveling {
    /// The decision's C mirror (TrackPlanBridge.h): NaN for every unknown number.
    init(_ decision: TrackLevelingDecision) {
        self.init()
        mode = switch decision.mode {
        case .off: UInt8(AsLevelingModeOff.rawValue)
        case .leveled: UInt8(AsLevelingModeLeveled.rawValue)
        case .unknownCut: UInt8(AsLevelingModeUnknownCut.rawValue)
        }
        source = switch decision.source {
        case .analysis: UInt8(AsLevelingSourceAnalysis.rawValue)
        case .tags: UInt8(AsLevelingSourceTags.rawValue)
        case .unknownCut: UInt8(AsLevelingSourceUnknownCut.rawValue)
        }
        continuousWithPrevious = decision.continuousWithPrevious ? 1 : 0
        let measuredRoles = Array(decision.roles.prefix(Int(AS_MAX_CHANNELS)))
        channelCount = UInt8(measuredRoles.count)
        Self.fill(&roles, with: measuredRoles, count: Int(AS_MAX_CHANNELS),
                  padding: UInt8(AsChannelRoleUnknown.rawValue))
        peakRateHz = decision.peakRate ?? 0
        loudnessLufs = decision.unfolded.loudness ?? .nan
        truePeakDbtp = decision.unfolded.truePeak ?? .nan
        let variants = Int(AS_FOLD_LFE_VARIANTS)
        if let folded = decision.folded {
            hasFolded = 1
            lfeVariant = UInt8(clamping: max(0, min(folded.variant, variants - 1)))
        }
        Self.fill(&foldedLufs, with: decision.folded?.loudness ?? [], count: variants, padding: .nan)
        Self.fill(&foldedTruePeakDbtp, with: decision.folded?.truePeak ?? [], count: variants, padding: .nan)
    }

    /// Fill the C array `tuple` (`count` elements of `Element`) from `values`, `padding` past their end.
    private static func fill<Tuple, Element>(_ tuple: inout Tuple, with values: [Element], count: Int,
                                             padding: Element) {
        precondition(MemoryLayout<Tuple>.size == count * MemoryLayout<Element>.stride, "not a C array of Element")
        withUnsafeMutablePointer(to: &tuple) { pointer in
            pointer.withMemoryRebound(to: Element.self, capacity: count) { elements in
                for index in 0 ..< count {
                    elements[index] = values.indices.contains(index) ? values[index] : padding
                }
            }
        }
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

    /// The listener changed the Leveling mode (`AudioPlaybackEngine.applyLevelingChange`): the audible track
    /// re-plans from `current` and both units glide there (0.15 s); `next` replaces the armed pick's decision (N11).
    /// Non-blocking: the leveling lock, the effects unit's borrow, and the fold's snapshot hand-over.
    func applyLevelingChange(current: TrackLevelingDecision, next: TrackLevelingDecision?) {
        let nextSaved = next.map(EngineLevelingState.Pending.savedProfiles(of:)) ?? []
        leveling.changeMode(current: current, next: next, nextSaved: nextSaved, effects: deliverToEffects)
    }

    // MARK: The requests and audibility (+Playback, +Gapless, +TrackLoudness)

    /// A start's decision, kept for its track's audibility (`engineQueue`, before `playFile`). A Pure start keeps
    /// none: leveling in Pure is deferred (record decision 1).
    func holdStartDecision(_ decision: TrackLevelingDecision?, for url: URL) {
        leveling.holdStart(decision.map { EngineLevelingState.Pending(url: url, decision: $0) })
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
