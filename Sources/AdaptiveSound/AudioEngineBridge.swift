import Accelerate
@preconcurrency import AVFoundation
import Foundation
import os

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
/// config re-establish) — OR is guarded by the leaf `os_unfair_lock` (`stateLock`, see
/// `AudioEngineBridge+SharedState.swift`) for the small set of fields the MainActor 20 Hz
/// poll reads while a queue writes. No field is mutated from two domains without that
/// discipline; the lock is a leaf (no other lock/queue taken while held) so no deadlock
/// cycle exists. The three `installTap` blocks (`+Graph.swift`) are the only render/tap
/// (RT) touchpoints and only read pre-allocated, lock-free state (SpectrumAnalyzer /
/// SpectrumDoubleBuffer / the C loudness-meter handle). The public API is therefore safe
/// to call from any thread — which is why the class can honestly be `Sendable` even though
/// the compiler cannot see the queue/lock model. An `actor` would violate RT-safety
/// (executor hops on the control path, cannot express the tap/render boundary).
final class AudioEngineBridge: AudioPlaybackEngine, @unchecked Sendable {
    var avEngine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
    /// Internal (not private) so `AudioEngineBridge+Playback.swift` can read/write it.
    var referenceToneBuffer: AVAudioPCMBuffer?

    // MARK: - Spectrum Analyzer

    /// Owns the FFT state and the lock-free double-buffer.
    /// Created in `initialize()` (off the audio thread) so all buffers are
    /// pre-allocated before the tap fires.
    var spectrumAnalyzer: SpectrumAnalyzer?

    /// RAII owner of the opaque BS.1770-5 LufsMeter handle (C bridge), fed from the same tap.
    /// Created in `allocateAnalysisState` (off the audio thread), dropped in the graph teardown
    /// AFTER `removeSpectrumTap()`. The wrapper's `deinit` is the backstop that closes the leak if a
    /// bridge is ever released without `shutdown()`. The RT mixer tap captures the wrapper's RAW
    /// `handle` once at install time (never the class), so no ARC touches the audio thread — see
    /// `AudioEngineBridge+Graph.swift`.
    var loudnessMeter: LoudnessMeterHandle?

    /// Tap is installed on mainMixerNode's output; the node's format fixes
    /// the sample rate that `SpectrumAnalyzer` must be initialised with.
    var tapInstalled = false

    /// The custom DSP effects AU node (N->N), inserted as `player -> effectsAU -> spatialAU` (M1).
    /// Held strongly for the engine's lifetime; detached + released in `shutdown()`.
    var dspAudioUnit: AVAudioUnit?

    /// The device-boundary spatial render AU (N->M, subtype 'aspz'), inserted as
    /// `effectsAU -> spatialAU -> mainMixer` (Sprint 5b M3-3). It is the stage that maps the
    /// source/processing width N to the device width M, so the mixer no longer naively downmixes
    /// (it runs at the device width M). For M3 the device width M == source width N, making the
    /// spatial AU a bit-exact identity route; S4 introduces the real M < N fold (binaural).
    /// Held strongly for the engine's lifetime; detached + released in `shutdown()`.
    var spatialAudioUnit: AVAudioUnit?

    // MARK: - Monitoring analyzers (per-channel before/after spectra)

    /// One spectrum analyzer PER CHANNEL for each tap point: `beforeAnalyzers` from the pre-DSP
    /// player-node tap, `afterAnalyzers` from the post-DSP effects-AU tap. Sized to the stream's
    /// channel count at init — N-channel by construction (stereo today; practical ceiling 7.1 / 8).
    /// Read by the Monitoring tab; never resized on the audio thread.
    var beforeAnalyzers: [SpectrumAnalyzer] = []
    var afterAnalyzers: [SpectrumAnalyzer] = []
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

    /// Backing storage for `currentDeviceID` — guarded by `stateLock`. The device selected by
    /// `selectDevice(_:)`, or the system default selected at `initialize()`. Pure Mode uses this to
    /// open the HAL engine on the right device. Access ONLY via the guarded accessors in
    /// `AudioEngineBridge+SharedState.swift` (`currentDeviceID` / `setCurrentDeviceID(_:)`).
    var storedCurrentDeviceID: UInt32 = 0

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
    /// snapshot, polled at 20 Hz on the MainActor by `currentSignalPath()` while it is written from
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
    /// Enhanced playhead, cached every time `currentPlaybackPosition()` resolves a real position (the
    /// view model polls it). Used to re-establish playback at the right point after an
    /// `AVAudioEngineConfigurationChange` — at that instant the player may already report no render
    /// time, so this cached value is the most recent reliable playhead. Also updated at gapless seams
    /// so the new track's position re-zeroes correctly. Access ONLY via the guarded accessors.
    var storedLastKnownEnhancedPositionSeconds: Double = 0

    // MARK: - Gapless / on-deck state (methods in AudioEngineBridge+Gapless.swift)

    /// The track armed to play gaplessly after the current one. `nil` means no next track is queued.
    /// All access is serialized on `resampleQueue` (same queue that owns the resampler session + all
    /// buffer scheduling). Written by `setNextTrack(_:)` (dispatched onto `resampleQueue`);
    /// consumed at EOF by the seam handler.
    var onDeckURL: URL?

    /// Monotonic count of completed gapless seams (track transitions). Incremented on `resampleQueue`
    /// at each real seam; read synchronously from `resampleQueue` by `trackTransitionCount()`.
    var gaplessTransitionCount: UInt64 = 0

    /// Set to `true` when the current track reaches EOF with no next track on deck. Cleared by the
    /// next `startAudio`. Read synchronously from `resampleQueue` by `playbackEnded()`.
    var gaplessPlaybackEnded: Bool = false

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

    /// Whether the Enhanced path is INTENDED to be playing — set when Enhanced playback starts,
    /// cleared on stop / device-loss / end-of-queue. The config-change + device-change re-establish
    /// uses this instead of the transient `playerNode.isPlaying`, which a hardware reconfiguration
    /// (a device connecting/disconnecting) can momentarily flip to `false` — causing the re-establish
    /// to bail and leave playback silently dead. Intent is the durable truth; the node state is not.
    var enhancedPlayIntent: Bool = false

    /// User preference for what happens when a NEW output device connects mid-playback (set by the
    /// view model from a Settings toggle). `true` (default) = "app-authoritative": re-pin the selected
    /// device so playback stays put. `false` = "follow": adopt the newly-connected device as the
    /// target. Consumed by `handleDeviceSetChange()`.
    var pinPlaybackToSelectedDevice: Bool = true

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

    /// CoreAudio property-listener token for the device-is-alive notification on the device Pure is
    /// rendering on. Registered when Pure starts; removed on teardown. On the device disappearing,
    /// playback pauses (see AudioEngineBridge+PureModeDeviceMonitor.swift).
    var deviceAliveListenerBlock: AudioObjectPropertyListenerBlock?

    /// The device the alive-listener was registered on, so we UNregister from the SAME device.
    var aliveListenerDeviceID: UInt32 = 0

    /// The EXACT dispatch queue the alive-listener block was registered on, retained so removal
    /// passes the identical queue instance rather than re-deriving one (F5). `AudioObjectRemove…`
    /// only unregisters when the (object, address, queue, block) tuple matches the Add call; a
    /// re-derived queue would silently fail to remove and leak the listener.
    var aliveListenerQueue: DispatchQueue?

    /// Invoked on the main thread when the available-output-device set changes. Set by the view
    /// model; fired by the `kAudioHardwarePropertyDevices` listener (see AudioEngineBridge+Devices).
    var onOutputDevicesChanged: (@MainActor () -> Void)?

    /// CoreAudio property-listener token for the device-list (add/remove) notification.
    /// Registered in `initialize()`, removed in `shutdown()`.
    var deviceListListenerBlock: AudioObjectPropertyListenerBlock?

    /// The EXACT dispatch queue the device-list listener was registered on, retained so removal
    /// passes the identical queue instance rather than re-deriving one (F5, same rationale as
    /// `aliveListenerQueue`).
    var deviceListListenerQueue: DispatchQueue?

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
    /// `setParameter`, `selectDevice`, `enumerateOutputDevices`, `initialize`, and `shutdown` route
    /// their bodies here (previously each dispatched onto the CONCURRENT `DispatchQueue.global()`,
    /// so they could interleave on `avEngine` / `playerNode` / `pureEngine` / `activePath`). One
    /// serial queue makes those transitions mutually exclusive (P2-B). It may call
    /// `resampleQueue.sync` (one-directional, engineQueue → resampleQueue); it must NEVER be the
    /// target of a `.sync` from resampleQueue / configChangeQueue, so no wait-cycle can form.
    let engineQueue = DispatchQueue(label: "com.adaptivesound.engine")

    /// Re-entrancy guard for `reestablishEnhancedAfterConfigChange`. Exclusively accessed on
    /// `configChangeQueue` (both the FOLLOW-mode dispatch and the config-change notification handler
    /// run there). A FOLLOW device-connect fires BOTH paths — the explicit `configChangeQueue.async`
    /// in `handleDeviceSetChange` AND the subsequent `AVAudioEngineConfigurationChange` notification —
    /// causing a second `seekEnhancedResampler` that abandons the first re-prime → audible dropout.
    /// This flag lets the second entry early-return. `defer` ensures it is always cleared.
    var isReestablishing: Bool = false

    // Engine lifecycle (initialize / shutdown) lives in AudioEngineBridge+Lifecycle.swift.

    // MARK: - Public spectrum read (called from main thread via ViewModel)

    /// Copy the latest 44 band magnitudes into `out`. Returns `false` if no
    /// data has been published yet (engine not running or no signal).
    @discardableResult
    func readSpectrumBands(into out: inout [Float]) -> Bool {
        return spectrumAnalyzer?.doubleBuffer.read(into: &out) ?? false
    }

    // MARK: - Monitoring read (per-channel before/after)

    /// Number of channels being monitored (the graph's channel count). 0 until the engine is ready.
    var monitorChannelCount: Int {
        afterAnalyzers.count
    }

    /// Copy the latest band magnitudes for one tap point + channel into `out`. Returns false if
    /// unavailable (engine not ready, channel out of range, or no data published yet).
    @discardableResult
    func readMonitorBands(_ tap: MonitorTap, channel: Int, into out: inout [Float]) -> Bool {
        let analyzers = (tap == .before) ? beforeAnalyzers : afterAnalyzers
        guard channel >= 0, channel < analyzers.count else { return false }
        return analyzers[channel].doubleBuffer.read(into: &out)
    }

    // EQ control plane (dspAudioUnitRef + publishEQGains) lives in AudioEngineBridge+EQControl.swift.

    func currentLoudness() -> LoudnessSnapshot {
        guard let meter = loudnessMeter?.handle else { return .unmeasured }
        let readout = loudnessMeterRead(meter)
        return LoudnessSnapshot(
            integratedLufs: readout.integratedLufs,
            shortTermLufs: readout.shortTermLufs,
            truePeakDb: readout.truePeakDb
        )
    }

    func currentSignalPath() -> SignalPathInfo {
        loadSignalPath()
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
