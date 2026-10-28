import AVFoundation
import Foundation
import LevelingKit
import PlaybackQueueKit
import SettingsKit

// MARK: - AudioPlaybackEngine Protocol + Default Implementations

/// Protocol boundary between AudioViewModel and the live audio engine.
///
/// Conforming types provide all I/O operations needed by AudioViewModel.
/// The protocol enables unit-testing of AudioViewModel without a live
/// AVFAudio engine: tests inject the one test double, `FakeEngine` (or `OnDeckEngineModel`, which
/// composes it), instead.
///
/// Concurrency contract: all methods may be called from a background Task.
/// Implementations are responsible for dispatching UI-bound side-effects to
/// the main actor if needed; the protocol itself is actor-agnostic.
///
/// MAIN-THREAD RULE (S10.8 G, the disconnect freeze): the view model calls every SYNCHRONOUS
/// requirement on the main thread, so none of them may call into AVFAudio (a node, the engine, its
/// I/O unit) or the CoreAudio HAL, take a lock held across such a call, or `.sync` onto a queue that
/// makes one. State comes back as ONE copy (`snapshot()`); the rest hand values to non-blocking
/// sinks, or read a value under a lock held only for the read. Anything that must touch the hardware
/// is `async`, or hands its work to an engine queue and answers through the snapshot
/// (`publishMasterGain` on Pure, `keepPureVolumeLoans`).
extension AudioPlaybackEngine {
    // MARK: Gapless defaults (overridden by the live engine + the mock)

    //
    // Declared as protocol requirements (below) for dynamic dispatch, with these no-op /
    // neutral defaults so a conformer that does not implement gapless still builds and behaves
    // as "one track then stop" — the pre-gapless behaviour.

    /// Supply (or clear, with `nil`) the track to play gaplessly after the current one. Default: no-op.
    func setNextTrack(_: URL?, ticket _: OnDeckTicket, leveling _: TrackLevelingDecision?) async {}

    /// Default: no-op — a conformer that does not level has nothing to re-plan.
    func applyLevelingChange(current _: TrackLevelingDecision, next _: TrackLevelingDecision?) {}

    /// Default: no device targeted (0). The live engine overrides with its `currentDeviceID`.
    func currentOutputDeviceID() -> UInt32 {
        0
    }

    /// Default: no-op. The live engine stores the preference and consults it on device changes.
    func setPinPlaybackToSelectedDevice(_: Bool) {}

    /// Default: no-op — no output rule to hand the choice to.
    func restoreChosenOutput(uid _: String?) {}

    /// Default: nothing chosen.
    func chosenOutputUID() -> String? {
        nil
    }

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishIntensity(_: Float) {}

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishCrossfeed(enabled _: Bool, strength _: CrossfeedStrength) {}

    /// Default: no-op. Conformers that host the DSP AU override this.
    func publishOutputTransport(_: UInt32) {}

    /// Default: no-op. Conformers with a player override this.
    func publishMasterGain(decibels _: Float) {}

    /// Default: no-op — no device volume is ever lowered.
    func keepPureVolumeLoans(in _: PureVolumeLoanJournal) {}

    /// Default: no-op — a conformer without per-channel analysers has nothing to run or rest.
    func setMonitorAnalysis(_: Bool) {}
}

protocol AudioPlaybackEngine: AnyObject, Sendable {
    // MARK: Lifecycle

    /// Initialize the engine and prepare for playback.
    /// Returns `true` on success.
    func initialize() async throws -> Bool

    /// Tear down the engine, release hardware resources.
    func shutdown() async throws

    // MARK: Playback

    /// Start playback of the audio file at `fileURL`, `startAt` seconds
    /// into it (0 = the top; a resume or a device move starts there, never from 0 then a seek).
    /// When `pureMode` is `true` and the device + file support it, the bit-perfect
    /// HAL path is used; otherwise the Enhanced (AVFAudio engine) path is used. `epoch` numbers the
    /// request: the snapshot's transport carries it from the start of the request on. `leveling` is the
    /// track's leveling decision (R1.1-B, level-and-fold §S3, B2): it travels with the request that makes
    /// the track audible, and the engine plans from it at that moment — once (B1). Pure ignores it (leveling
    /// in Pure is deferred, record decision 1).
    ///
    /// Newest stands (council C-15). The view model numbers its starts, stops and seeks in the order
    /// the user asks; they can reach the engine in another order. One older than a request the engine
    /// has already begun was overtaken: it returns at once and has no effect — never an error.
    func startAudio(fileURL: URL, pureMode: Bool, startAt: Double, epoch: UInt64,
                    leveling: TrackLevelingDecision) async throws

    /// Stop all playback immediately; the on-deck pick goes with it (a stop begins a new playback, so
    /// every on-deck request made before it is stale — invariant 5 below). `epoch` numbers the request,
    /// as for `startAudio`, and an overtaken stop is dropped the same way. `pausing`: playback is meant
    /// to resume from here, so on Pure the output device keeps the volume Pure set (founder decision
    /// 2026-10-16, `PureVolumeEvent.paused`); otherwise playback ended (Stop, the end of the queue, the
    /// queue cleared, quit), Pure is left, and the device gets its own level back.
    func stopAudio(epoch: UInt64, pausing: Bool) async throws

    // MARK: Gapless / continuous playback (poll-based — the view model reads a snapshot at 20 Hz)

    //
    // # GaplessController contract (S6 Tier-3 §4)
    //
    // `setNextTrack` plus the transport snapshot (`transitionCount`, `ended`, `position`) form the
    // GaplessController behavioural contract that BOTH live paths — the Enhanced bridge
    // (`AudioEngineBridge+Gapless.swift` / `+GaplessRoll.swift`) and the Pure HAL C-ABI
    // (`PureModeBridge.h` → `GaplessSource`) — must satisfy identically. The view model drives every
    // transition off the snapshot's `transitionCount`.
    //
    // Invariants (asserted by the shared conformance suite):
    //   1. Arm → seam → `transitionCount` increments by EXACTLY ONE per seam.
    //   2. `setNextTrack(nil)` cancels the on-deck track (no seam occurs from a cleared deck).
    //   3. End-of-queue (a seam with nothing on deck) sets `ended`.
    //   4. `position` RE-ZEROES at the seam: the first sample of the new track reports ~0.0, NOT
    //      cumulative time across the seam. VERIFIED PARITY: Pure re-zeroes per track natively
    //      (`PureModeBridge.h` `pureModeEnginePositionSeconds`: "RESTARTS at 0 at each gapless seam");
    //      Enhanced re-bases at every seam in `bumpTransitionCount` (sets
    //      `enhancedPositionBaseSeconds = -(sampleTime/rate)`), called from EVERY seam path in
    //      `+GaplessRoll.swift`.
    //   5. Newest per playback (council D41). Every request carries an `OnDeckTicket`: the epoch of
    //      the start it follows, and its place in the order the view model made requests. A start or
    //      stop begins a new playback (a seek does not; one older than the engine's playback changes
    //      nothing); the engine applies only the newest request of its current playback and drops
    //      every other, whatever order they arrive in — a dropped request has no effect.
    //   6. Applied at once. An admitted request replaces the on-deck pick immediately: Enhanced sets
    //      the slot; Pure takes the old pick off at once (it either already played or never will),
    //      then arms the new one when its file opens, if it is still the newest. A pick that is
    //      still opening when the current track ends, can't join gaplessly, or can't be read leaves
    //      the deck empty: the current track ends (`ended`), and the view model starts the pick
    //      fresh — a short gap, the right song.
    //   7. The end is final. A track that ended with nothing on deck never seams into a pick armed
    //      later; the view model starts it fresh.
    //
    // What the view model may rely on: once no request is in flight, the deck holds the newest
    // request's pick, or is empty and `ended` follows. What it may NOT (the seam reports a count,
    // not which track it played — follow-up F1 closes both):
    //   A2.  A request not yet admitted when the current track ends — the rest of the main-thread
    //        turn, one hop, and any `engineQueue` backlog (Enhanced: then `resampleQueue`'s) — finds
    //        the old pick still armed: the old pick plays while the view model shows the new one.
    //   A2'. An edit made after a seam but before the view model's tick saw it (up to 50 ms, plus
    //        the 33 ms clock) is shown as playing, while the pick the seam took plays.
    //
    // ## Pure's polling side effect (S6 Tier-3 §4.4)
    //
    // Polling the Pure seam counter (`pureModeEnginePollTrackAdvance`) also reaps the seam-retired
    // decode source off-RT (joins its decode thread), so it must be polled regularly. The live
    // engine's own transport clock does that, off the main thread (AudioEngineBridge+TransportClock).

    /// Supply the track to play gaplessly after the current one finishes, or `nil` to clear the
    /// on-deck track — the request numbered `ticket` (invariants 5–7 above). The engine
    /// pre-schedules (Enhanced) / arms (Pure) it so the transition is seamless — no `stop()`, no
    /// inserted silence. Re-supply after each transition to keep one track on deck. Reuses the
    /// current path (Enhanced/Pure) and mode. Returns once the request is settled. Default impl: no-op.
    /// `leveling` is the pick's leveling decision (`nil` with a `nil` pick): it is armed with the pick, in the
    /// D41 order, and planned from when the pick becomes audible at the seam (R1.1-B, §S3, B2).
    ///
    /// Contract: `setNextTrack(nil)` CANCELS the on-deck track — it clears the armed slot and disarms
    /// any seam hook so no queued track silently begins later. A subsequent end-of-current-track with
    /// an empty deck sets `ended` rather than seaming. (Enhanced: clears `onDeckURL` + the EOF hooks
    /// on `resampleQueue`; Pure: `pureModeEngineClearNextTrack`, which joins the dropped source off-RT.)
    func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket, leveling: TrackLevelingDecision?) async

    /// The listener changed the Leveling mode (R1.1-B, §1.3 "when the planner runs", item 2): the audible
    /// track re-plans from `current` and both units glide there (0.15 s); `next` replaces the armed pick's
    /// decision (N11). Automatic changes never move a playing track; this is the listener's own act.
    /// Synchronous, non-blocking (the main-thread rule). Default impl: no-op.
    func applyLevelingChange(current: TrackLevelingDecision, next: TrackLevelingDecision?)

    /// The engine's state as the main thread may read it — the ONE read the view model makes of it:
    /// the transport as the engine last sampled it off the main thread (the playhead within the
    /// current track, re-zeroed at each seam; the seam count; whether the queue ran out), the signal
    /// path, the loudness and the EQ's design rate. A copy of published values — it never waits on
    /// the player, the engine or the hardware, however long they are stuck. The transport may be a
    /// clock tick stale; after `startAudio`, `stopAudio` and `seek` return, it reflects them.
    func snapshot() -> EngineSnapshot

    /// Seek to `seconds` from the start of the current file, on either path (the one rule:
    /// `SeekTarget`). A place at or past the end ends the track — the transport's `ended` — as if it
    /// had played out. Throws `AudioBridgeError.seekFailed` when the seek did not happen — a target
    /// that is not a number, a file that no longer opens, a Pure decoder that could not move — and
    /// playback carries on exactly where it was. `epoch` numbers the request, as for `startAudio`, and
    /// an overtaken seek is dropped the same way (not a failure).
    func seek(to seconds: Double, epoch: UInt64) async throws

    // MARK: Master Gain

    /// Publish Master Gain — the app's own level in dB, ≤ 0 (−∞ = silent; `MasterGainLaw`). On
    /// Enhanced the player plays it at its linear gain from then on, on every Enhanced start and after
    /// a rebuild too. On Pure the bit-perfect stream is not scaled: the output device's own volume is
    /// turned down by it instead (`MasterGainOnPure` — at Pure's start, and as it moves), off the main
    /// thread. Synchronous; calls apply in the order made. Default impl: no-op.
    func publishMasterGain(decibels: Float)

    /// Keep Pure's device-volume loans in `journal` (over the launch's defaults): the engine reads the loans
    /// an earlier run left there and puts back the level of each device that is here and still reads what
    /// Pure set (or was setting) — a crash, or a device that went away mid-Pure, leaves no device turned
    /// down — and from then on writes the journal ahead of every change it makes to a device (H-2).
    /// Returns at once (the HAL work runs on an engine queue). Call at engine-ready. Default impl: no-op.
    func keepPureVolumeLoans(in journal: PureVolumeLoanJournal)

    // MARK: DSP Parameters

    /// Publish the EQ to the live DSP AU (the engine side of the Sprint EQ contract): the 31
    /// `points` (dB, one per band, `EQBands`) that are drawn, and whether the EQ plays at all.
    /// `isOn == false` plays the flat curve whatever `points` hold. `comparing`: Compare is held, so the
    /// song plays without the EQ at the level the EQ plays at — level-matched (R1.1-B, §7). Synchronous,
    /// off-RT, non-throwing; the engine validates its input (count, finite, ±12 dB) and coalesces bursts.
    /// No-op if no live AU (e.g. engine not initialized).
    func publishEQ(points: [Float], isOn: Bool, comparing: Bool)

    /// Publish a new Reimagine intensity value ([0, 1]) to the live DSP AU.
    /// No-op if the AU is not yet instantiated. Default impl: no-op.
    func publishIntensity(_ intensity: Float)

    /// Tell the live DSP AU which kind of output it plays on: the device's
    /// `kAudioDevicePropertyTransportType` (0 = unknown). Founder decision 29: the EQ-only path's
    /// limiter ceiling is −0.1 dBTP on a wired or built-in output and −1 dBTP on Bluetooth.
    /// Synchronous, off-RT. No-op if the AU is not yet instantiated. Default impl: no-op.
    func publishOutputTransport(_ transportType: UInt32)

    /// Publish a crossfeed state change to the live DSP AU (QW1 §3).
    /// No-op if the AU is not yet instantiated. Default impl: no-op. Synchronous + off-RT: it
    /// borrows the AU under the leaf lock and hands the state to the kernel (no suspension point).
    func publishCrossfeed(enabled: Bool, strength: CrossfeedStrength)

    // MARK: Device Enumeration

    /// Return the full list of available output devices with real CoreAudio data.
    func enumerateOutputDevices() async throws -> [AudioDeviceModel]

    /// The user picked the output device with this CoreAudio id in the device menu: the app plays on
    /// it, and "Keep playback on this device" holds it from now on — by UID, so it is the device
    /// playback returns to when it reconnects. Only the user's picks come here: never the device the
    /// app starts on, nor one the engine moved to. Returns `true` on success.
    func selectDevice(_ deviceID: UInt32) async throws -> Bool

    /// The output device the engine plays on (picked by the user, the default at launch, or moved by
    /// the output rule), so the view model shows the matching `AudioDeviceModel` and keeps its
    /// selection in step with the bridge's `currentDeviceID`. `0` if none. Default impl: `0`.
    func currentOutputDeviceID() -> UInt32

    /// Set "Keep playback on this device". `true` = the device the user chose wins over the system
    /// default (re-asserted while Enhanced plays or starts; returned to when it reconnects after a
    /// loss); turning it on chooses the device in use. `false` = follow the system default.
    /// Default: no-op.
    func setPinPlaybackToSelectedDevice(_ pin: Bool)

    /// Hand back the device the user chose before the last quit (DEV-1), by UID (`nil`: none): "Keep
    /// playback on this device" holds it again. Not a pick — the device the engine launched on stays
    /// its device until the output rule moves to the chosen one, which it does as soon as that device
    /// is here (never changing the system default while nothing plays). At engine-ready. Returns at
    /// once: the rule runs off the main thread. Default: no-op.
    func restoreChosenOutput(uid: String?)

    /// The UID of the device the user chose — by a pick, or by turning "Keep playback on this device"
    /// on — `nil` if none: what the listener's settings keep. A read under a lock held only for the
    /// read. Default: `nil`.
    func chosenOutputUID() -> String?

    /// Invoked on the main thread when the output changed: a device was added or removed, the
    /// engine adopted a device (the system default, or the chosen device back), or it paused for a
    /// lost device. The view model re-reads the devices and the engine's device
    /// (`currentOutputDeviceID`) in response.
    var onOutputDevicesChanged: (@MainActor () -> Void)? { get set }

    // MARK: Spectrum

    /// Read the latest 44 spectrum band magnitudes into `out`.
    /// Returns `false` if no data has been published yet.
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool

    // MARK: Monitoring (per-channel before/after spectra)

    /// Number of channels being monitored (the graph's channel count). 0 until the engine is ready.
    var monitorChannelCount: Int { get }

    /// Read the latest per-channel band magnitudes for the given tap point + channel into `out`.
    /// Returns `false` if unavailable (not ready, channel out of range, or no data yet).
    @discardableResult
    func readMonitorBands(_ tap: MonitorTap, channel: Int, into out: inout [Float]) -> Bool

    /// Run the per-channel analysers while Monitoring shows (`true`), rest them otherwise (council
    /// C-52): the main thread says so as the tab appears and goes. Non-blocking (one atomic store).
    /// Default: no-op.
    func setMonitorAnalysis(_ isOn: Bool)
}
