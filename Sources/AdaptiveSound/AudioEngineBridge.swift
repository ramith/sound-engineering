import Accelerate
import AudioFormatKit
import AVFoundation
import Foundation

// MARK: - AudioEngineBridge

/// Concrete `AudioPlaybackEngine` that drives `AVAudioEngine` + CoreAudio.
///
/// Device enumeration is wired to real CoreAudio data via the C-ABI functions
/// exported from `AUAudioUnit.mm` (`enumerateOutputDevicesC`, `selectOutputDeviceC`).
/// No mock data — every `AudioDeviceModel` reflects an actual system device.
final class AudioEngineBridge: AudioPlaybackEngine {
    var avEngine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
    /// Internal (not private) so `AudioEngineBridge+Playback.swift` can read/write it.
    var referenceToneBuffer: AVAudioPCMBuffer?

    // MARK: - Spectrum Analyzer

    /// Owns the FFT state and the lock-free double-buffer.
    /// Created in `initialize()` (off the audio thread) so all buffers are
    /// pre-allocated before the tap fires.
    var spectrumAnalyzer: SpectrumAnalyzer?

    /// Opaque BS.1770-5 LufsMeter handle (C bridge), fed from the same tap.
    /// Created in `initialize()`, destroyed in `shutdown()`.
    var loudnessMeter: UnsafeMutableRawPointer?

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

    // MARK: - Pure-Mode stored state (methods live in AudioEngineBridge+PureMode.swift)

    /// The device selected by `selectDevice(_:)`, or the system default selected at
    /// `initialize()`. Pure Mode uses this to open the HAL engine on the right device.
    var currentDeviceID: UInt32 = 0

    /// Opaque Pure-Mode engine handle (created lazily in `startPure`).
    /// Destroyed by `pureModeEngineDestroy` in `stopAudio` / `shutdown`.
    var pureEngine: UnsafeMutableRawPointer?

    /// Which output path is currently active.
    var activePath: OutputPathKind = .enhanced

    /// Latest signal-path snapshot; polled lock-free by `currentSignalPath()`.
    var cachedSignalPath: SignalPathInfo = .init()

    /// URL of the last successfully scheduled file, used by the device-change fallback
    /// to restart playback on the new device without re-opening the file picker.
    var lastFileURL: URL?

    /// Absolute position offset (seconds) for the Enhanced path. AVAudioPlayerNode's sampleTime
    /// restarts at 0 on every play(), so after a seek (stop + scheduleSegment(from:) + play) we add
    /// this (= the seek target) to report the true playhead. 0 on a fresh from-start play.
    var enhancedPositionBaseSeconds: Double = 0

    /// Last non-nil Enhanced playhead, cached every time `currentPlaybackPosition()` resolves a real
    /// position (the view model polls it). Used to re-establish playback at the right point after an
    /// `AVAudioEngineConfigurationChange` — at that instant the player may already report no render
    /// time, so this cached value is the most recent reliable playhead. Also updated at gapless seams
    /// so the new track's position re-zeroes correctly. Internal (not private) so the gapless
    /// extension in `AudioEngineBridge+Gapless.swift` can update it.
    var lastKnownEnhancedPositionSeconds: Double = 0

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

    /// Called on `resampleQueue` when the streaming resampler reaches EOF and is about to stop
    /// chaining. The gapless extension installs this to roll into the next track without a gap.
    /// The handler receives the session that just ended and the live player node. Cleared on stop /
    /// seek / track-change (via `stopEnhancedResampler`) so a stale handler cannot fire.
    var onResamplerEOF: ((EnhancedResampleSession, AVAudioPlayerNode) -> Void)?

    /// Whether the most recent `startAudio` call requested Pure mode.
    var pureModeRequested: Bool = false

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

    /// Invoked on the main thread when the available-output-device set changes. Set by the view
    /// model; fired by the `kAudioHardwarePropertyDevices` listener (see AudioEngineBridge+Devices).
    var onOutputDevicesChanged: (() -> Void)?

    /// CoreAudio property-listener token for the device-list (add/remove) notification.
    /// Registered in `initialize()`, removed in `shutdown()`.
    var deviceListListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Graph state

    /// Top-level engine-graph state. The `.reconfiguring` transition is driven by
    /// `reconfigureGraph(to:)`. The trigger that calls it (track channel-count change at
    /// file load) is wired in `startAudio` via `configureGraphForSource`.
    enum GraphState {
        case idle
        case running(channelCount: Int)
        case reconfiguring
    }

    var graphState: GraphState = .idle

    /// Observer for `AVAudioEngineConfigurationChange`. Without it, a hardware route change
    /// (Bluetooth disconnect, USB unplug, default-device switch) leaves `AVAudioEngine` stopped and
    /// the app silently goes quiet. Registered in `initialize()`, removed in `shutdown()`.
    /// Internal (not private) so `AudioEngineBridge+ConfigChange.swift` can write it.
    var configChangeObserver: NSObjectProtocol?

    /// Serial queue on which the `AVAudioEngineConfigurationChange` handler runs. A single device
    /// switch can post the notification more than once in quick succession; serializing keeps the
    /// re-establish sequence (stop → re-prime → play) from interleaving across concurrent handlers.
    let configChangeQueue = DispatchQueue(label: "com.adaptivesound.config-change")

    /// Re-entrancy guard for `reestablishEnhancedAfterConfigChange`. Exclusively accessed on
    /// `configChangeQueue` (both the FOLLOW-mode dispatch and the config-change notification handler
    /// run there). A FOLLOW device-connect fires BOTH paths — the explicit `configChangeQueue.async`
    /// in `handleDeviceSetChange` AND the subsequent `AVAudioEngineConfigurationChange` notification —
    /// causing a second `seekEnhancedResampler` that abandons the first re-prime → audible dropout.
    /// This flag lets the second entry early-return. `defer` ensures it is always cleared.
    var isReestablishing: Bool = false

    // MARK: - Initialize

    func initialize() async throws -> Bool {
        // Register both custom AU subclasses once per process (idempotent on the C++ side).
        registerAdaptiveAudioUnitSubclass()
        registerSpatialRendererAUSubclass()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // Capture the current default output device so Pure Mode can open the right
                // HAL engine. Updated in selectDevice(_:) and by the device-change listener.
                self.currentDeviceID = getDefaultOutputDeviceID()

                let engine = AVAudioEngine()
                self.avEngine = engine
                self.observeConfigurationChanges(of: engine)

                // Refresh the device picker when devices are added/removed (BT connect/disconnect).
                self.registerDeviceListListener()

                // Use stereo 48 kHz float to support any input file (mono, stereo, WebM, etc).
                // AVAudio converts any file format to match this; it is also the AU bus format.
                guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2) else {
                    continuation.resume(returning: false)
                    return
                }

                // Attach the player now, but DON'T connect it to the mixer here — the player feeds
                // the effects AU below. Connecting player -> mixer too would create a second (dry)
                // signal path into the mixer.
                let player = AVAudioPlayerNode()
                self.playerNode = player
                engine.attach(player)

                // Instantiate both AUs and build the two-AU graph; the (nested) completion handlers
                // resume the continuation exactly once for this path.
                self.instantiateAndBuildGraph(engine: engine, player: player, format: format,
                                              completion: continuation.resume(returning:))
            }
        }
    }

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

    // EQ control plane (dspAudioUnitHandle + publishEQGains) lives in AudioEngineBridge+EQControl.swift.

    func currentLoudness() -> LoudnessSnapshot {
        guard let meter = loudnessMeter else { return .unmeasured }
        let readout = loudnessMeterRead(meter)
        return LoudnessSnapshot(
            integratedLufs: readout.integratedLufs,
            shortTermLufs: readout.shortTermLufs,
            momentaryLufs: readout.momentaryLufs,
            peakDb: readout.peakDb
        )
    }

    // MARK: - Shutdown

    func shutdown() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // Stop the streaming-resampler loop FIRST (bump generation + drop session) so no
                // in-flight buffer schedules onto the graph we're about to tear down.
                self.stopEnhancedResampler()

                // Remove CoreAudio property listeners before tearing down anything else.
                self.unregisterDeviceAliveListener()
                self.unregisterDeviceListListener()

                self.removeSpectrumTap()
                if let observer = self.configChangeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.configChangeObserver = nil
                }

                // Stop + destroy the Pure-Mode engine if live (releases hog mode + device rate).
                if self.activePath == .pure {
                    self.tearDownPure()
                } else if let engine = self.pureEngine {
                    // Orphaned handle (e.g. failed mid-start): always destroy to avoid a hog leak.
                    pureModeEngineDestroy(engine)
                    self.pureEngine = nil
                }

                if let playerNode = self.playerNode, playerNode.isPlaying {
                    playerNode.stop()
                }
                if let engine = self.avEngine, engine.isRunning {
                    engine.stop()
                }
                // Detach both AUs (graph is stopped; safe to mutate) and drop the strong refs.
                if let engine = self.avEngine {
                    if let effectsUnit = self.dspAudioUnit { engine.detach(effectsUnit) }
                    if let spatialUnit = self.spatialAudioUnit { engine.detach(spatialUnit) }
                }
                self.dspAudioUnit = nil
                self.spatialAudioUnit = nil
                self.avEngine = nil
                self.playerNode = nil
                self.referenceToneBuffer = nil
                self.spectrumAnalyzer = nil
                self.graphState = .idle
                self.beforeAnalyzers = []
                self.afterAnalyzers = []
                self.activePath = .enhanced
                self.cachedSignalPath = .init()
                // Tap already removed above, so no callback can touch the meter now.
                if let meter = self.loudnessMeter {
                    loudnessMeterDestroy(meter)
                    self.loudnessMeter = nil
                }
                continuation.resume()
            }
        }
    }

    func currentSignalPath() -> SignalPathInfo {
        cachedSignalPath
    }

    // Device enumeration + selection live in AudioEngineBridge+Devices.swift.
    // Playback transport lives in AudioEngineBridge+Playback.swift.
}

// AudioDeviceModel.DeviceType.sortOrder lives in AudioEngineBridge+Devices.swift (used by the
// device-enumeration sort there).
// Configuration-change resilience lives in AudioEngineBridge+ConfigChange.swift.
