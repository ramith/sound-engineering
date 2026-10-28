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
// `setNextTrack(…, leveling:)`); the bridge keeps it beside the request until the track becomes audible, then
// plans ONCE (`asPlanTrack`, B1) against the one output state, and hands the same plan to both units in the same
// turn: the effects unit (the leveling gain under the cap) and the spatial unit (the fold's trim and LFE gain,
// lane 2's — `setFoldPlanSink`). A listener's mode change re-plans the audible track and replaces the armed
// decision; an output change re-plans protectively with the gain frozen (F5).
//
// THE OUTPUT STATE (M2) is assembled by lane 2 on `engineQueue` — at `configureGraphForSource` and at every
// re-establish — and handed here (`applyOutputState`); its `transportType` is the view model's hand-over
// (`publishOutputTransport`, a value, never read on main), which lane 2 reads back with `levelingOutputTransport()`.
//
// THREADS. A track becomes audible on `engineQueue` (a start) or on `resampleQueue` (a gapless seam), a mode change
// arrives from the main thread, the output state from `engineQueue`: so the state is guarded by its own lock,
// held only to read, plan and hand the plan on (no hardware call, no wait). NEVER call into it while holding the
// bridge's `stateLock` (the effects unit's borrow takes that lock inside this one).

/// What the bridge keeps for leveling between a start or arm and the moment its track becomes audible: the
/// decision each request carries, the output state, and what the planner made of them. Guarded by its own lock;
/// any thread.
final class EngineLevelingState: Sendable {
    /// The fold's half of a plan, delivered by the spatial unit's owner (lane 2), with why it came — a fresh start
    /// snaps, a gapless seam glides 10 ms, a mode change 0.15 s, an output change is the protective re-plan — so the
    /// fold moves exactly as the effects unit does (NI-4).
    typealias FoldPlanSink = @Sendable (AsTrackPlan, AsOutputState, AsPlanEvent) -> Void

    private struct Held {
        var output = AsOutputState.unknownStereo
        var foldPlanSink: FoldPlanSink?
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

    func setOutputTransport(_ transportType: UInt32) {
        held.withLock { $0.output.transportType = transportType }
    }

    func setOutputState(_ state: AsOutputState) {
        held.withLock { $0.output = state }
    }

    func setFoldPlanSink(_ sink: FoldPlanSink?) {
        held.withLock { $0.foldPlanSink = sink }
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
        leveling.setOutputState(state)
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
    /// re-plans and glides; the armed decision is replaced. Step-1 seam: no effect yet.
    func applyLevelingChange(current _: TrackLevelingDecision, next _: TrackLevelingDecision?) {}
}
