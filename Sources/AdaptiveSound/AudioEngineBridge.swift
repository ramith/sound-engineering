import Accelerate
import AudioDSP
@preconcurrency import AVFoundation
import EQEditKit
import Foundation
import os
import OutputDeviceKit
import PlaybackQueueKit
import Synchronization
import TrackLoudnessKit

// MARK: - AudioEngineBridge

/// Concrete `AudioPlaybackEngine` that drives `AVAudioEngine` + CoreAudio.
///
/// Device enumeration is wired to real CoreAudio data via the C-ABI functions
/// exported from `AUAudioUnit.mm` (`enumerateOutputDevicesC`, `selectOutputDeviceC`).
/// No mock data — every `AudioDeviceModel` reflects an actual system device.
///
/// `@unchecked Sendable` invariant: this type is a hand-rolled isolation domain, NOT a
/// Swift actor and NOT `@MainActor`. ALL mutable stored state is confined to one of the
/// bridge's serial dispatch queues — `engineQueue` (transport/graph/device lifecycle),
/// `resampleQueue` (streaming-resampler + gapless state), `configChangeQueue` (device/
/// config re-establish), `deviceVolumeQueue` (the Pure device's volume) — OR is guarded by the
/// leaf `os_unfair_lock` (`stateLock`, see `AudioEngineBridge+SharedState.swift`) for the small
/// set of fields the main thread's `snapshot()` and borrows read while a queue writes. The main
/// thread never waits on a queue or on AVFAudio: docs/architecture/architecture.md, "Threading
/// rules (app ↔ engine)". That is the model, held by convention, not by a type: the council found
/// it broken in three places (BR-1) that the one transport owner (W2) is to close — the
/// configuration-change re-establish drives the engine and player from `configChangeQueue` while
/// `engineQueue` runs the transport (a play-intent re-check narrows that race, it does not close
/// it); a failed gapless roll restarts through `playFile` on a global queue
/// (`openNextFileOrRestart`); and the two AU instantiate completions finish the graph build on
/// whatever queue AVFAudio calls them on (`instantiateAndBuildGraph`). The lock is a leaf (no
/// other lock/queue taken while held) so no deadlock
/// cycle exists. The three `installTap` blocks (`+Graph.swift`) are the only render/tap
/// (RT) touchpoints and only read pre-allocated, lock-free state (SpectrumAnalyzer /
/// SpectrumTripleBuffer / the C loudness-meter handle). The public API is therefore safe
/// to call from any thread — which is why the class can honestly be `Sendable` even though
/// the compiler cannot see the queue/lock model. An `actor` would violate RT-safety
/// (executor hops on the control path, cannot express the tap/render boundary).
final class AudioEngineBridge: AudioPlaybackEngine, @unchecked Sendable {
    var avEngine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?

    // MARK: - Tap analysis (spectrum, loudness, monitoring)

    /// The taps' analysis objects — the Now-Playing spectrum analyzer, the BS.1770-5 loudness meter
    /// and the per-channel monitoring analyzers — as ONE value, guarded by `stateLock` (access ONLY
    /// via `tapAnalysis` / `setTapAnalysis`). Built and resized on `engineQueue`, read by the main
    /// thread's spectrum / meter / monitoring polls as a strong copy: a teardown or re-init
    /// replacing it can no longer free an object under a read in flight (review: the snapshot's
    /// meter read raced `retryInitialization`). The RT taps capture what they need once, at install.
    var storedTapAnalysis = TapAnalysis()

    /// Whether Monitoring shows: its analysers run only then. Captured by the before / after taps.
    let monitorAnalysis = MonitorAnalysisSwitch()

    /// Tap is installed on mainMixerNode's output; the node's format fixes
    /// the sample rate that `SpectrumAnalyzer` must be initialised with.
    var tapInstalled = false

    /// The custom DSP effects AU (N->N), inserted as `player -> effectsAU -> spatialAU` (M1): the
    /// graph's node and the `AUAudioUnit` the control plane publishes to, as ONE value so they can
    /// never disagree. Guarded by `stateLock`; access ONLY via `effectsNode`, `withEffectsAU` and
    /// `setEffectsUnit`. Held for the engine's lifetime; detached + released in `shutdown()`.
    var storedEffectsUnit: GraphUnit?

    /// Borrows of the effects AU in flight (`withEffectsAU`). The teardown waits for it to reach 0
    /// before releasing the AU, so the release — and the AU's Realizer barrier — is never a
    /// main-thread borrow's. Named acquire/release atomic.
    let effectsAUBorrows = Atomic<Int>(0)

    // MARK: - Transport clock (methods in AudioEngineBridge+TransportClock.swift)

    /// The transport as the clock last sampled it — what `snapshot()` hands the main thread.
    /// Published on `engineQueue` only (the clock, and the top and end of start / stop / seek).
    let transportSnapshots = SnapshotChannel(TransportSnapshot())

    /// The clock: a timer on `engineQueue` that samples the transport ~30 times a second while
    /// something plays (started by a start, cancelled by a stop, the device-loss pause and the
    /// teardown). Confined to `engineQueue`.
    var transportClock: DispatchSourceTimer?

    /// The epoch of the latest transport operation the engine has begun (`TransportSnapshot.epoch`),
    /// stamped on every sample; an operation older than it is dropped (`beginTransportOperation`).
    /// Confined to `engineQueue`.
    var transportEpoch: UInt64 = 0

    /// The device-boundary spatial render AU (N->M, subtype 'aspz'), inserted as
    /// `effectsAU -> spatialAU -> mainMixer` (Sprint 5b M3-3): the stage that maps the source width N
    /// to the device boundary M — a bit-exact identity route when M == N, the BS.775 stereo fold and its
    /// backstop when the device is narrower (R1.1-B). The graph's node and the `AUAudioUnit` the fold's
    /// parameters are published to, as ONE value (level-and-fold §8, M1). Guarded by `stateLock`; access
    /// ONLY via `spatialNode`, `withSpatialAU` and `setSpatialUnit`. Held for the engine's lifetime;
    /// detached + released in `shutdown()`.
    var storedSpatialUnit: GraphUnit?

    /// Borrows of the spatial AU in flight (`withSpatialAU`); the teardown waits for 0, as for the
    /// effects AU. Named acquire/release atomic.
    let spatialAUBorrows = Atomic<Int>(0)

    // MARK: - Monitoring taps (per-channel before/after spectra; analyzers in `storedTapAnalysis`)

    /// Pre-DSP tap lives on the player node; post-DSP (after) tap on the EFFECTS AU output bus —
    /// NOT the mixer (which carries the device width M once the spatial AU is in the graph), and
    /// NOT the spatial AU (which renders the device-width signal; "after DSP" monitors the
    /// N-channel processed signal). Both stay N-channel by construction.
    var beforeTapInstalled = false
    var afterTapInstalled = false

    /// Heap-allocated `os_unfair_lock` backing the leaf `stateLock` that guards the shared
    /// playback-context fields (see `AudioEngineBridge+SharedState.swift`). Allocated once for
    /// the bridge's lifetime so the pointer is stable across calls (an `os_unfair_lock` must be
    /// locked/unlocked through a stable address). Freed in `deinit`.
    let stateLockPtr: os_unfair_lock_t = {
        let ptr = os_unfair_lock_t.allocate(capacity: 1)
        ptr.initialize(to: os_unfair_lock())
        return ptr
    }()

    // MARK: - Pure-Mode stored state (methods live in AudioEngineBridge+PureMode.swift)

    /// Backing storage for the app's output devices — guarded by `stateLock` (`OutputDeviceSelection`,
    /// OutputDeviceKit): the device it plays on (`currentDeviceID`: picked with `selectDevice(_:)`, the
    /// system default at `initialize()`, or adopted by the output rule; Pure opens its HAL engine on it),
    /// the device the user chose, which "Keep playback on this device" holds, and that switch. One value,
    /// so the output rule reads them together; written from the main actor (the switch), `engineQueue`
    /// and `configChangeQueue`. Access ONLY via the guarded accessors in
    /// `AudioEngineBridge+SharedState.swift` (`currentDeviceID` / `outputSelection` /
    /// `updateOutputSelection(_:)`).
    var storedOutputSelection = OutputDeviceSelection()

    /// RAII owner of the opaque Pure-Mode engine handle (created lazily in `startPure`). The wrapper
    /// is dropped — running its `deinit` → `pureModeEngineDestroy` (slow HAL teardown) — by the
    /// controlled teardown, OUTSIDE `stateLock`, on `engineQueue`; its `deinit` is the backstop that
    /// closes the leak if a bridge is ever released without `shutdown()`. Guarded by `stateLock`: it
    /// is written from `engineQueue` (start/stop/shutdown) AND `configChangeQueue` (device-loss) and
    /// read by the MainActor 20 Hz poll, so access it ONLY via the guarded accessors in
    /// `AudioEngineBridge+SharedState.swift` (`withPureEngine` to borrow its `handle`,
    /// `detachPureEngineForTeardown` to relinquish ownership, `pureEngineHandle`/`setPureEngine` for
    /// lifecycle bookkeeping) — never directly.
    var pureEngine: PureModeSession?

    /// Which output path is currently active. Guarded by `stateLock` (same cross-domain read/write
    /// pattern as `pureEngine`); access ONLY via `activePathKind` / `setActivePath` / `withPureEngine`
    /// in `AudioEngineBridge+SharedState.swift` — never directly.
    var activePath: OutputPathKind = .enhanced

    /// Backing storage for `cachedSignalPath` — guarded by `stateLock`. Latest signal-path
    /// snapshot, read at 20 Hz by the main thread's `snapshot()` while it is written from
    /// engineQueue / configChangeQueue / the device-loss path. Access ONLY via the guarded
    /// accessors in `AudioEngineBridge+SharedState.swift`.
    var storedCachedSignalPath: SignalPathInfo = .init()

    /// Backing storage for `lastFileURL` — guarded by `stateLock`. URL of the last successfully
    /// scheduled file, used by the device-change fallback to restart playback on the new device
    /// without re-opening the file picker. Access ONLY via the guarded accessors.
    var storedLastFileURL: URL?

    /// Backing storage for `enhancedPositionBaseSeconds` — guarded by `stateLock`. Absolute position
    /// offset (seconds) for the Enhanced path. AVAudioPlayerNode's sampleTime restarts at 0 on every
    /// play(), so after a seek (stop + scheduleSegment(from:) + play) we add this (= the seek target)
    /// to report the true playhead. 0 on a fresh from-start play. Access ONLY via the guarded
    /// accessors.
    var storedEnhancedPositionBaseSeconds: Double = 0

    /// Backing storage for `lastKnownEnhancedPositionSeconds` — guarded by `stateLock`. Last non-nil
    /// Enhanced playhead, cached by the transport clock whenever it reads a real position. Used to
    /// re-establish playback at the right point after an `AVAudioEngineConfigurationChange` — at
    /// that instant the player may already report no render time, so this cached value is the most
    /// recent reliable playhead. Also updated at gapless seams so the new track's position re-zeroes
    /// correctly. Access ONLY via the guarded accessors.
    var storedLastKnownEnhancedPositionSeconds: Double = 0

    // MARK: - Gapless / on-deck state (methods in AudioEngineBridge+Gapless.swift)

    /// Which on-deck request the engine applies (`OnDeckGate`, council D41): the playback session it
    /// is in — begun by every start and stop, numbered by the request's epoch — and the newest
    /// request admitted in it. Every `setNextTrack` passes it first; any other request is dropped,
    /// whatever order the requests arrive in. Confined to `engineQueue`.
    var onDeckGate = OnDeckGate()

    /// The track armed to play gaplessly after the current one. `nil` means no next track is queued.
    /// All access is serialized on `resampleQueue` (same queue that owns the resampler session + all
    /// buffer scheduling). Written by an admitted Enhanced `setNextTrack` (`armEnhancedOnDeck`, handed
    /// over from `engineQueue` in admission order); consumed at EOF by the seam handler.
    var onDeckURL: URL?

    /// Monotonic count of completed gapless seams (track transitions): written on `resampleQueue`
    /// at each real seam (the only writer), read by the transport clock without waiting on that
    /// queue. Named acquire/release atomic; use `gaplessTransitionCount`.
    let gaplessTransitionCounter = Atomic<UInt64>(0)

    /// `true` once the current track reached EOF with no next track on deck; cleared by the next
    /// `startAudio`. Written on `resampleQueue` / `engineQueue`, read by the transport clock.
    /// Named acquire/release atomic; use `gaplessPlaybackEnded`.
    let gaplessEndedFlag = Atomic<Bool>(false)

    /// Called on `resampleQueue` when the 48 kHz passthrough `scheduleFile` reaches playback-end
    /// (`.dataPlayedBack` fires). The gapless extension installs this to chain the next track or
    /// set `gaplessPlaybackEnded`. Cleared on stop/seek so a stale handler cannot fire.
    var onPassthroughEOF: ((AVAudioPlayerNode) -> Void)?

    /// Epoch for the 48 kHz passthrough schedules — the passthrough twin of `resampleGeneration`.
    /// `player.stop()` FIRES any pending `.dataPlayedBack` completion, indistinguishable from a
    /// real end-of-track: with a next track armed, the seam handler would consume it and start
    /// the WRONG song on every stop that isn't an EOF (device-switch re-establish and passthrough
    /// seek both stop+reschedule — the founder's wrong-song/stale-selection bug). Every schedule
    /// site captures the epoch it was installed under; the completion abandons at fire time if a
    /// stop/seek/reschedule has advanced it. Owned by `resampleQueue`, like all seam state.
    var passthroughGeneration: UInt64 = 0

    /// Called on `resampleQueue` when the streaming resampler reaches EOF and is about to stop
    /// chaining. The gapless extension installs this to roll into the next track without a gap.
    /// The handler receives the session that just ended and the live player node. Cleared on stop /
    /// seek / track-change (via `stopEnhancedResampler`) so a stale handler cannot fire.
    var onResamplerEOF: ((EnhancedResampleSession, AVAudioPlayerNode) -> Void)?

    /// The track loudness analyzer (EQ1c): profiles the audible track and the next one for the
    /// loudness-neutral EQ gain (`AudioEngineBridge+TrackLoudness.swift`). Thread-safe; its
    /// requests return at once and run in order.
    let loudnessAnalyzer = TrackLoudnessAnalyzer(log: { logUX($0) })

    /// The leveling state for the audible track and the one on deck (R1.1-B, level-and-fold §S3). Its type is
    /// lane 1's (`AudioEngineBridge+Leveling.swift`); this line is the coordinator's, so lane 2, which owns
    /// this file in W4, never touches it. Guarded by its own lock; any queue (a track becomes audible on `engineQueue`
    /// and on `resampleQueue`; a mode change arrives from main).
    var leveling = EngineLevelingState()

    /// Whether the Enhanced path is INTENDED to be playing — set when Enhanced playback starts,
    /// cleared on stop / device-loss / end-of-queue. The config-change + device-change re-establish
    /// uses this instead of the transient `playerNode.isPlaying`, which a hardware reconfiguration
    /// (a device connecting/disconnecting) can momentarily flip to `false` — causing the re-establish
    /// to bail and leave playback silently dead. Intent is the durable truth; the node state is not.
    /// A named acquire/release atomic (`enhancedPlayIntent`), so the device-loss decision reads and
    /// clears it without waiting on `resampleQueue`, which can be busy in AVFAudio or a file open.
    let enhancedPlayIntentFlag = Atomic<Bool>(false)

    // MARK: - Enhanced streaming-resampler state (methods in AudioEngineBridge+EnhancedResampler.swift)

    /// Live streaming-resampler session, non-nil only while an Enhanced rate-mismatched file is
    /// being played through `AVAudioConverter` (file rate != 48 kHz graph rate). The 48 kHz
    /// passthrough path (`scheduleFile`) leaves this `nil` and is byte-identical to before.
    /// All access is serialized on `resampleQueue`; published/read off the audio thread only.
    var resampleSession: EnhancedResampleSession?

    /// Serial queue owning ALL converter access + buffer scheduling for the streaming-resampler
    /// path. Read → convert → schedule and the completion-driven chaining all run here, so the
    /// converter's internal rate-conversion state is touched from exactly one thread.
    let resampleQueue = DispatchQueue(label: "com.adaptivesound.enhanced-resampler")

    /// Generation/epoch counter for the streaming resampler. Bumped on every start / seek / stop /
    /// teardown. Each in-flight read→convert→schedule iteration captures the generation it started
    /// under and bails (schedules nothing more) the moment it no longer matches — so a seek, stop,
    /// track change, or reconfigure cleanly abandons every queued-but-not-yet-played buffer.
    var resampleGeneration: UInt64 = 0

    /// A test rig's view of what the Enhanced path schedules and when its completions are handed on
    /// (`StreamObserver`); `nil` in the app.
    let streamObserver = Mutex<(any StreamObserver)?>(nil)

    // MARK: - Master Gain (methods in AudioEngineBridge+MasterGain.swift)

    /// The app's Master Gain in dB, which the player plays (`applyMasterGain`). Confined to
    /// `engineQueue`: written by `publishMasterGain`, read where a player is built or started.
    var masterGainDecibels: Float = MasterGainLaw.unity

    /// The device whose volume Pure holds (and Master Gain steers), and the listener following that
    /// volume (`watchDeviceVolume`) — for as long as the hold lasts, through a pause; `nil` otherwise.
    /// Guarded by `stateLock`: set and taken on `engineQueue` (`enterPureVolume`, `pureVolumeEvent`),
    /// read on `deviceVolumeQueue`.
    var deviceVolumeWatch: DeviceVolumeWatch?

    /// Serial queue for the Pure device's volume: Master Gain on Pure (`MasterGainOnPure` — the entry,
    /// the slider's moves, leaving, the loans a previous run left) and the device's change listener —
    /// HAL calls that must never run on the main thread.
    let deviceVolumeQueue = DispatchQueue(label: "com.adaptivesound.device-volume")

    /// Master Gain on Pure: the loan of the device's volume Pure holds, and those not yet put back.
    /// Confined to `deviceVolumeQueue`.
    var masterGainOnPure = MasterGainOnPure()

    /// The Master Gain the Pure device was last steered to (the listener's change is read against it).
    /// Confined to `deviceVolumeQueue`.
    var pureGain: Float = MasterGainLaw.unity

    /// The newest Master Gain for the Pure device, not yet applied, and whether a drain is posted
    /// (latest value wins — `steerPureVolume`). Guarded by `stateLock`.
    var pendingPureGain: Float?
    var pureGainDrainPosted = false

    // MARK: - Output-device monitoring state (methods in AudioEngineBridge+OutputDeviceMonitor.swift)

    /// The device-list (`kAudioHardwarePropertyDevices`) and system-default-output
    /// (`kAudioHardwarePropertyDefaultOutputDevice`) listeners. Registered in `initialize()`, removed
    /// in the engine teardown; both confined to `engineQueue`.
    var deviceListListener: AudioPropertyListener?
    var defaultOutputListener: AudioPropertyListener?

    /// The `kAudioDevicePropertyDeviceIsAlive` listener on the app's device (`currentDeviceID`), on
    /// Enhanced and Pure alike. Re-bound whenever the target changes; confined to `configChangeQueue`.
    var targetAliveListener: AudioPropertyListener?

    /// Whether the output listeners are live (initialize → teardown). Confined to
    /// `configChangeQueue`, so an event that arrives after teardown can't re-bind a listener.
    var isMonitoringOutput = false

    /// Invoked on the main thread when the device list or the app's device changes (a device
    /// connected or went away; the app adopted the system default; playback paused for a lost
    /// device). Set by the view model, which re-reads the devices (`refreshDevices`).
    var onOutputDevicesChanged: (@MainActor () -> Void)?

    /// Observer for `AVAudioEngineConfigurationChange`. Without it, a hardware route change
    /// (Bluetooth disconnect, USB unplug, default-device switch) leaves `AVAudioEngine` stopped and
    /// the app silently goes quiet. Registered in `initialize()`, removed in `shutdown()`.
    /// Internal (not private) so `AudioEngineBridge+ConfigChange.swift` can write it.
    var configChangeObserver: NSObjectProtocol?

    /// Serial queue on which the `AVAudioEngineConfigurationChange` handler runs. A single device
    /// switch can post the notification more than once in quick succession; serializing keeps the
    /// re-establish sequence (stop → re-prime → play) from interleaving across concurrent handlers.
    let configChangeQueue = DispatchQueue(label: "com.adaptivesound.config-change")

    /// Serial queue that owns ALL transport / graph mutation: `startAudio`, `stopAudio`, `seek`,
    /// `publishMasterGain`, `selectDevice`, `enumerateOutputDevices`, `initialize`, and `shutdown` route
    /// their bodies here (previously each dispatched onto the CONCURRENT `DispatchQueue.global()`,
    /// so they could interleave on `avEngine` / `playerNode` / `pureEngine` / `activePath`). One
    /// serial queue makes those transitions mutually exclusive (P2-B). It may call
    /// `resampleQueue.sync` (one-directional, engineQueue → resampleQueue); it must NEVER be the
    /// target of a `.sync` from resampleQueue / configChangeQueue, so no wait-cycle can form.
    let engineQueue = DispatchQueue(label: "com.adaptivesound.engine")

    /// Re-entrancy guard for `reestablishEnhancedAfterConfigChange`. Exclusively accessed on
    /// `configChangeQueue`, where every output event is decided (AudioEngineBridge+OutputDeviceMonitor).
    /// `defer` ensures it is always cleared.
    var isReestablishing: Bool = false

    // Engine lifecycle (initialize / shutdown) lives in AudioEngineBridge+Lifecycle.swift.

    // MARK: - Public spectrum read (called from main thread via ViewModel)

    /// Copy the latest 44 band magnitudes into `out`. Returns `false` if no
    /// data has been published yet (engine not running or no signal).
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool {
        tapAnalysis.spectrum?.frames.read(into: &out) ?? false
    }

    // MARK: - Monitoring read (per-channel before/after)

    /// Number of channels being monitored (the graph's channel count). 0 until the engine is ready.
    var monitorChannelCount: Int {
        tapAnalysis.after.count
    }

    /// Copy the latest band magnitudes for one tap point + channel into `out`. Returns false if
    /// unavailable (engine not ready, channel out of range, or no data published yet).
    @discardableResult
    func readMonitorBands(_ tap: MonitorTap, channel: Int, into out: inout [Float]) -> Bool {
        let analysis = tapAnalysis
        let analyzers = (tap == .before) ? analysis.before : analysis.after
        guard channel >= 0, channel < analyzers.count else { return false }
        return analyzers[channel].frames.read(into: &out)
    }

    /// Run the per-channel analysers (Monitoring shows) or rest them. One atomic store.
    func setMonitorAnalysis(_ isOn: Bool) {
        monitorAnalysis.set(isOn)
    }

    // EQ control plane (withEffectsAU + publishEQ) lives in AudioEngineBridge+EQControl.swift.

    /// The engine's state for the main thread (`AudioPlaybackEngine.snapshot`): the transport clock's
    /// last sample, the signal path (a copy under `stateLock`, whose holders never call out) with S2's two
    /// engine reads — the fold the spatial unit plays and whether the crossfeed played (atomics, through
    /// borrows of the AUs) — the meter's atomics (through a strong copy of the meter) and the EQ design rate
    /// (an atomic, through a borrow of the AU). No AVFAudio, no HAL, no queue hop.
    func snapshot() -> EngineSnapshot {
        var signalPath = loadSignalPath()
        if signalPath.path == .enhanced {
            signalPath.fold = foldReadout()
            signalPath.crossfeedEngaged = crossfeedEngagedNow()
        }
        return EngineSnapshot(transport: transportSnapshots.read(), signalPath: signalPath,
                              loudness: loudnessReadout(), eqDesignRate: eqSampleRate())
    }

    /// The fold the spatial unit plays (`asSpatialFoldState`: atomics, through a counted borrow), or `nil`
    /// when it doesn't fold or isn't live.
    private func foldReadout() -> FoldState? {
        var state = AsFoldState()
        guard withSpatialAU({ asSpatialFoldState($0, &state) }) == true, state.folding else { return nil }
        return FoldState(sourceChannels: Int(state.sourceChannels), outputChannels: Int(state.outputChannels),
                         fromPlan: state.fromPlan, trimDb: state.trimDb, lfeGain: state.lfeGain,
                         backstopPeakGrDb: state.backstopPeakGrDb)
    }

    /// The playback tap's loudness: atomics the meter publishes (`loudnessMeterRead`), read through
    /// a strong copy of the meter so a re-init can't free it mid-read.
    private func loudnessReadout() -> LoudnessSnapshot {
        guard let meter = tapAnalysis.meter else { return .unmeasured }
        let readout = withExtendedLifetime(meter) { loudnessMeterRead(meter.handle) }
        return LoudnessSnapshot(
            integratedLufs: readout.integratedLufs,
            shortTermLufs: readout.shortTermLufs,
            truePeakDb: readout.truePeakDb
        )
    }

    deinit {
        // Free the heap-allocated leaf lock. By the time the bridge deallocates, no queue work or
        // listener can still reference it (shutdown() has torn everything down and removed the
        // CoreAudio listeners), so this is a plain leaf cleanup.
        stateLockPtr.deinitialize(count: 1)
        stateLockPtr.deallocate()
    }

    // Device enumeration + selection live in AudioEngineBridge+Devices.swift.
    // Playback transport lives in AudioEngineBridge+Playback.swift.
}

// AudioDeviceModel.DeviceType.sortOrder lives in AudioEngineBridge+Devices.swift (used by the
// device-enumeration sort there).
// Configuration-change resilience lives in AudioEngineBridge+ConfigChange.swift.
