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
    private var referenceToneBuffer: AVAudioPCMBuffer?

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

    // MARK: - Monitoring analyzers (per-channel before/after spectra; Sprint 5 M3)

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

    // MARK: - Graph state (scaffold for the multichannel reconfigure lifecycle; Sprint 5b)

    /// Top-level engine-graph state. Introduced in S0-M3; the `.reconfiguring` transition is now
    /// driven by `reconfigureGraph(to:)` (Sprint 5b M2-c). The trigger that calls it (track
    /// channel-count change at file load) is wired in M2-d (`startAudio` -> `configureGraphForSource`).
    enum GraphState {
        case idle
        case running(channelCount: Int)
        case reconfiguring
    }

    var graphState: GraphState = .idle

    /// Observer for `AVAudioEngineConfigurationChange`. Without it, a hardware route change
    /// (Bluetooth disconnect, USB unplug, default-device switch) leaves `AVAudioEngine` stopped and
    /// the app silently goes quiet. Registered in `initialize()`, removed in `shutdown()`.
    private var configChangeObserver: NSObjectProtocol?

    /// Serial queue on which the `AVAudioEngineConfigurationChange` handler runs. A single device
    /// switch can post the notification more than once in quick succession; serializing keeps the
    /// re-establish sequence (stop → re-prime → play) from interleaving across concurrent handlers.
    let configChangeQueue = DispatchQueue(label: "com.adaptivesound.config-change")

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

    // MARK: - Monitoring read (per-channel before/after; Sprint 5 M3)

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

    // MARK: - DSP AU access (Sprint 5 M2 control plane)

    /// Opaque pointer to the underlying `AUAudioUnit`, for the C-ABI `publishTargetState` /
    /// `setAUParameter` bridge that the EQ Realizer (M2) will drive. `nil` until `initialize()`
    /// has instantiated the AU. Borrowed (passUnretained) — callers must not retain it past
    /// `shutdown()`; the `AVAudioUnit` owns the underlying instance.
    var dspAudioUnitHandle: UnsafeMutableRawPointer? {
        guard let unit = dspAudioUnit?.auAudioUnit else { return nil }
        return Unmanaged.passUnretained(unit).toOpaque()
    }

    /// Compute + publish the EQ biquad cascade for `gainsDb` (31 bands) to the live AU.
    /// The coefficient design sample rate is read from the AU output bus (the negotiated rate),
    /// falling back to the 48 kHz graph format. No-op if the AU isn't live.
    func publishEQGains(_ gainsDb: [Float]) {
        guard gainsDb.count == 31, let handle = dspAudioUnitHandle else { return }
        // Design coefficients for the AU's negotiated output rate (graph is 48 kHz; fall back
        // to that if the bus isn't queryable). AUAudioUnitBusArray is not a Swift collection.
        var sampleRate = 48000.0
        if let busArray = dspAudioUnit?.auAudioUnit.outputBusses, busArray.count > 0 {
            sampleRate = busArray[0].format.sampleRate
        }
        _ = gainsDb.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return publishEQBandGains(handle, base, UInt32(gainsDb.count), sampleRate)
        }
    }

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

    // Device enumeration + selection live in AudioEngineBridge+Devices.swift (extension).

    // MARK: - Playback

    func startAudio(fileURL: URL?, pureMode: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    // Record the intent for the device-change fallback restart path.
                    self.lastFileURL = fileURL
                    self.pureModeRequested = pureMode

                    // A fresh startAudio always begins a new playback context: clear the end-of-queue
                    // sentinel and the on-deck slot so the new play starts clean (the caller must
                    // re-arm on-deck after startAudio if it wants gapless from the first track).
                    // Both values live on resampleQueue, but startAudio always runs before any
                    // resampler loop is active (the prior session is stopped below), so writing them
                    // here (on DispatchQueue.global) before the resampler is started is race-free.
                    self.gaplessPlaybackEnded = false
                    self.onDeckURL = nil

                    // Attempt Pure path when requested, a file is provided, and capability allows.
                    if pureMode, let url = fileURL {
                        let viable = self.evaluatePureViable(fileURL: url, deviceID: self.currentDeviceID)
                        if viable {
                            // Tear down any live Enhanced playback before entering Pure
                            // (keep the graph intact for fast fallback — just stop the player).
                            self.stopEnhancedPlayback()
                            let started = self.startPure(fileURL: url, deviceID: self.currentDeviceID)
                            if started {
                                continuation.resume(returning: ())
                                return
                            }
                            // Pure engine started but achievedState.running == 0 → fall through
                            // to Enhanced. Record that we fell back.
                            NSLog("[AudioEngineBridge] Pure Mode start failed — falling back to Enhanced")
                            self.cachedSignalPath.fellBackToEnhanced = true
                        } else {
                            self.cachedSignalPath.fellBackToEnhanced = true
                        }
                    } else {
                        self.cachedSignalPath.fellBackToEnhanced = false
                    }

                    // If Pure was active, stop+destroy it before entering Enhanced
                    // (releases hog mode + restores device rate).
                    if self.activePath == .pure {
                        self.tearDownPure()
                    }

                    // Enhanced path (original startAudio body).
                    guard let engine = self.avEngine, let playerNode = self.playerNode else {
                        throw AudioBridgeError.engineNotInitialized
                    }

                    if !engine.isRunning {
                        try engine.start()
                    }

                    self.installSpectrumTap()

                    if let url = fileURL {
                        // playFile emits the mode-specific "Enhanced started ... (passthrough|resample)"
                        // line. Append only the Pure-fallback note here so it isn't double-logged.
                        try self.playFile(at: url, engine: engine, playerNode: playerNode)
                        if self.cachedSignalPath.fellBackToEnhanced {
                            logUX("Enhanced started '\(url.lastPathComponent)' (fell back from Pure)")
                        }
                    } else {
                        self.playReferenceTone(on: playerNode)
                        logUX("Enhanced started reference tone")
                    }

                    self.activePath = .enhanced
                    self.enhancedPlayIntent = true
                    self.cachedSignalPath = SignalPathInfo(
                        path: .enhanced,
                        decision: .fallbackEnhanced,
                        fellBackToEnhanced: self.cachedSignalPath.fellBackToEnhanced
                    )

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Open `fileURL`, drive the M2-d multichannel load sequence, then schedule + play it.
    ///
    /// Sequence (the M2-d contract): read N + the source channel layout from the opened file,
    /// `configureGraphForSource` (reconfigure the graph to N — a same-count no-op for stereo — THEN
    /// publish the layout tag to the kernel for correct BS.1770-5 weights), and only AFTER that
    /// stop the player + schedule + play. Reconfiguring before scheduling means the file is queued
    /// onto the graph already settled at its width.
    func playFile(at fileURL: URL, engine _: AVAudioEngine, playerNode: AVAudioPlayerNode) throws {
        // Establish security-scoped access for sandboxed macOS file access.
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AudioBridgeError.unsupportedFormat(fileURL.pathExtension)
        }

        // 1. Read the source width N and (optional) layout tag from the processing format.
        let processingFormat = audioFile.processingFormat
        let channelCount = processingFormat.channelCount
        let channelLayout = processingFormat.channelLayout

        // 2. Reconfigure the graph to N, THEN publish the layout to the kernel (M2-d). Stereo
        //    sources hit the same-count no-op, so the existing stereo path is unchanged.
        configureGraphForSource(channelCount: channelCount, channelLayout: channelLayout)

        // 3. Stop + reset the player before scheduling so the new file replaces (not queues after)
        //    the current one. Also stop any prior streaming-resampler session (bumps the generation
        //    so its in-flight buffers abandon themselves) before this new track supersedes it.
        stopEnhancedResampler()
        if playerNode.isPlaying {
            playerNode.stop()
        }
        // Fresh play schedules the whole file from frame 0 → no position offset. (A later seek sets
        // this to the seek target; see currentPlaybackPosition.)
        enhancedPositionBaseSeconds = 0

        // 4. Branch on rate. When the file is already 48 kHz the existing `scheduleFile` path is an
        //    exact passthrough (the engine performs no SRC), so keep it BYTE-IDENTICAL. Only when the
        //    file rate differs from the 48 kHz graph rate do we engage the high-quality streaming
        //    resampler — bounding the new code's blast radius to rate-mismatched files. If the
        //    converter can't be created / primes nothing, fall back to `scheduleFile` (default SRC).
        let fileRate = processingFormat.sampleRate
        let graphRate = playerNode.outputFormat(forBus: 0).sampleRate
        if fileRate == graphRate {
            // 48 kHz passthrough: byte-identical to the pre-gapless path. The completion callback
            // type `.dataPlayedBack` fires after the hardware has played the last sample, which is
            // the correct seam point for gapless. When no next track is armed the handler is nil and
            // the player simply stops at end-of-file (pre-gapless behaviour, unchanged).
            //
            // NOTE: AVAudioFile / ExtAudioFile trims AAC priming silence and MP3 LAME
            // delay/padding via the file's edit list (kExtAudioFileProperty_ClientDataFormat +
            // kAFInfoDictionary_ApproximateDuration). Apple handles this automatically on this
            // path; we must NOT disable or override it. Pure/FFmpeg trim is Stage 2.
            // swiftlint:disable:next line_length
            playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak playerNode] _ in
                guard let self, let livePlayer = playerNode else { return }
                self.resampleQueue.async { self.onPassthroughEOF?(livePlayer) }
            }
            playerNode.play()
            logUX("Enhanced started '\(fileURL.lastPathComponent)' (\(Int(graphRate)) passthrough)")
            return
        }

        let started = startEnhancedResampler(audioFile: audioFile, player: playerNode, startFrame: 0)
        if started {
            logUX("Enhanced started '\(fileURL.lastPathComponent)' "
                + "(resample \(Int(fileRate))→\(Int(graphRate)) max)")
        } else {
            // Converter unavailable / primed nothing → keep playback working via the proven path.
            playerNode.scheduleFile(audioFile, at: nil)
            playerNode.play()
            logUX("Enhanced started '\(fileURL.lastPathComponent)' "
                + "(resample \(Int(fileRate))→\(Int(graphRate)) FELL BACK to default SRC)")
        }
    }

    /// Fallback path when no file is supplied: schedule a 1 kHz reference tone on the player.
    private func playReferenceTone(on playerNode: AVAudioPlayerNode) {
        referenceToneBuffer = generateReferenceTone(
            frequency: 1000.0,
            duration: 5.0,
            sampleRate: 48000.0
        )

        if let buffer = referenceToneBuffer {
            if !playerNode.isPlaying {
                playerNode.play()
            }
            playerNode.scheduleBuffer(buffer, at: nil)
        }
    }

    func stopAudio() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if self.activePath == .pure {
                    self.tearDownPure()
                } else {
                    self.stopEnhancedPlayback()
                }
                // Clear the on-deck slot on user stop: a stop is a deliberate abort, not an
                // end-of-queue, so the armed next track must not silently begin playing later.
                // Serialized on resampleQueue so it cannot race with an in-flight seam handler.
                self.resampleQueue.async { self.onDeckURL = nil }
                self.enhancedPlayIntent = false
                self.removeSpectrumTap()
                self.referenceToneBuffer = nil
                self.activePath = .enhanced
                self.cachedSignalPath = .init()
                continuation.resume()
            }
        }
    }

    func currentPlaybackPosition() -> Double? {
        // Route to the active path.
        if activePath == .pure, let engine = pureEngine {
            let pos = pureModeEnginePositionSeconds(engine)
            return pos > 0 ? pos : nil
        }
        // Enhanced path: AVAudioPlayerNode's sampleTime counts from 0 at EACH play() — it is
        // time-since-play, not absolute file position. A seek does stop()+scheduleSegment(from:)+
        // play(), which restarts sampleTime at 0, so we add the seek target (enhancedPositionBaseSeconds,
        // 0 on a fresh play) to report the true playhead.
        guard let playerNode, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return nil
        }
        let position = enhancedPositionBaseSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
        // Cache the freshest reliable playhead for the config-change re-establish path.
        lastKnownEnhancedPositionSeconds = position
        return position
    }

    func currentSignalPath() -> SignalPathInfo {
        cachedSignalPath
    }

    func setParameter(_ id: UInt32, value: Float) async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if id == 0 {
                    // Pure path: never apply software gain to the bit-perfect stream. Instead drive
                    // the device's HARDWARE master volume (analog/HW domain → stays bit-perfect), so
                    // the in-app slider controls volume even without exclusive hog mode. A device with
                    // no settable master volume returns 0 (volume then via the OS / device only).
                    if self.activePath == .pure {
                        // Volume routing is logged once at the view-model layer (coalesced); not
                        // here — setParameter fires per slider tick and would spam the log.
                        _ = pureModeSetDeviceVolume(self.currentDeviceID, value)
                        continuation.resume()
                        return
                    }
                    // Enhanced path: master gain parameter → player node volume.
                    if let playerNode = self.playerNode {
                        playerNode.volume = value
                    }
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - AudioEngineBridge configuration-change resilience

///
/// Kept in a same-file extension (not the class body) so it stays close to the engine while not
/// counting toward the class's body length; `private` engine state is still reachable (file scope).
extension AudioEngineBridge {
    /// Resume rendering after a hardware configuration change (route / default-device / format
    /// change), which stops `AVAudioEngine` — otherwise the app silently goes quiet on a Bluetooth
    /// or USB change (incl. a device merely *connecting* and stealing the system default).
    func observeConfigurationChanges(of engine: AVAudioEngine) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.configChangeQueue.async {
                guard let self, let engine = self.avEngine else { return }
                logUX("config-change fired: path=\(self.activePath == .pure ? "Pure" : "Enhanced") "
                    + "engineRunning=\(engine.isRunning) playerPlaying=\(self.playerNode?.isPlaying ?? false) "
                    + "intent=\(self.enhancedPlayIntent) default=\(getDefaultOutputDeviceID()) "
                    + "selected=\(self.currentDeviceID)")
                // While Pure Mode owns the device (hog mode + a per-track nominal-rate change),
                // those very changes fire this notification. The Enhanced AVAudioEngine is
                // intentionally stopped and must NOT try to restart on the hogged device — doing so
                // fails with -10875 (invalid output HW format) and contends for the device. The
                // Pure path runs its own HAL engine; leave it alone. Device loss for the Pure path
                // is handled (paused) by the CoreAudio device-alive listener in
                // AudioEngineBridge+PureModeDeviceMonitor.swift.
                guard self.activePath != .pure else { return }
                // After a device-loss pause we are intentionally stopped — don't auto-restart on the
                // config change that the disconnect itself fires. Cleared on the next startAudio.
                guard !self.cachedSignalPath.interrupted else { return }
                self.reestablishEnhancedAfterConfigChange(engine: engine)
            }
        }
    }

    /// Re-establish the Enhanced path after a route / default-device / format change.
    ///
    /// A configuration change stops `AVAudioEngine` AND flushes every buffer queued on the player
    /// node. Restarting the engine + calling `play()` is enough for the 48 kHz `scheduleFile`
    /// passthrough, but it does NOT refill the streaming-resampler's `scheduleBuffer` chain (the
    /// completion chain that was feeding the player is broken when its buffers are flushed) — which
    /// is why a device switch on a rate-mismatched file went intermittently silent. So we re-drive
    /// the scheduler from the current playhead, reusing the seek machinery, on the now-current
    /// output device. Runs on `configChangeQueue` (serialized — see `observeConfigurationChanges`).
    /// Internal (not private) so the device-set handler in `AudioEngineBridge+Devices.swift` can
    /// drive a re-establish when "follow the newly-connected device" mode adopts a new default.
    func reestablishEnhancedAfterConfigChange(engine: AVAudioEngine) {
        // Use the durable play-INTENT, not `playerNode.isPlaying`: a reconfiguration (a device
        // connecting/disconnecting) can momentarily report the node as not-playing, and gating on
        // that left playback silently dead after e.g. a Bluetooth device connected mid-track.
        let wasPlaying = enhancedPlayIntent

        // Capture the playhead BEFORE restarting (the player may stop reporting a render time across
        // the reconfiguration; `lastKnownEnhancedPositionSeconds` is the freshest reliable value).
        let resumePos = currentPlaybackPosition() ?? lastKnownEnhancedPositionSeconds

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                NSLog("[AudioEngineBridge] engine restart after configuration change failed: \(error)")
                return
            }
        }

        guard wasPlaying, let player = playerNode else { return }

        if resampleSession != nil {
            // Rate-mismatched file: re-prime the streaming resampler from the playhead. (engine.start()
            // + play() alone leave the flushed buffer queue empty → silence.)
            if !seekEnhancedResampler(to: resumePos, player: player), !player.isPlaying {
                player.play()
            }
        } else if let url = lastFileURL {
            // 48 kHz passthrough: re-schedule the remaining segment from the playhead onto the new
            // device, guaranteeing fresh buffers regardless of whether the old schedule survived.
            seekEnhancedBestEffort(url: url, player: player, to: resumePos)
        } else if !player.isPlaying {
            player.play() // reference tone / no source file
        }
        enhancedPositionBaseSeconds = resumePos
        logUX("Enhanced re-established after configuration change at \(secs(resumePos))s")
    }
}

// AudioDeviceModel.DeviceType.sortOrder lives in AudioEngineBridge+Devices.swift (used by the
// device-enumeration sort there).
