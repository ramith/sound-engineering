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

    /// Whether the most recent `startAudio` call requested Pure mode.
    var pureModeRequested: Bool = false

    /// CoreAudio property-listener token for the device-is-alive notification on the device Pure is
    /// rendering on. Registered when Pure starts; removed on teardown. On the device disappearing,
    /// playback pauses (see AudioEngineBridge+PureModeDeviceMonitor.swift).
    var deviceAliveListenerBlock: AudioObjectPropertyListenerBlock?

    /// The device the alive-listener was registered on, so we UNregister from the SAME device.
    var aliveListenerDeviceID: UInt32 = 0

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

    /// Resume rendering after a hardware configuration change (route / default-device / format
    /// change), which stops `AVAudioEngine` — otherwise the app silently goes quiet on a Bluetooth
    /// or USB change. (Full device-width / exclusive re-evaluation is Phase B; here we resume the
    /// existing graph so playback continues.)
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            DispatchQueue.global().async {
                guard let self, let engine = self.avEngine else { return }
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
                let wasPlaying = self.playerNode?.isPlaying ?? false
                if !engine.isRunning {
                    do {
                        try engine.start()
                    } catch {
                        NSLog("[AudioEngineBridge] engine restart after configuration change failed: \(error)")
                        return
                    }
                }
                if wasPlaying, let player = self.playerNode, !player.isPlaying {
                    player.play()
                }
            }
        }
    }

    func shutdown() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // Remove the Pure-Mode device-alive listener before tearing down anything else.
                self.unregisterDeviceAliveListener()

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
                        try self.playFile(at: url, engine: engine, playerNode: playerNode)
                    } else {
                        self.playReferenceTone(on: playerNode)
                    }

                    self.activePath = .enhanced
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
        //    the current one, then schedule + play onto the freshly settled graph.
        if playerNode.isPlaying {
            playerNode.stop()
        }
        playerNode.scheduleFile(audioFile, at: nil)
        playerNode.play()
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
        // Enhanced path: derive the playhead from the player node's render time.
        // sampleTime counts from 0 at play() and accumulates while playing —
        // divide by the rate to get seconds.
        guard let playerNode, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return nil
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    func currentSignalPath() -> SignalPathInfo {
        cachedSignalPath
    }

    func setParameter(_ id: UInt32, value: Float) async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if id == 0 {
                    // In the Pure path, volume is device/OS-owned (bit-perfect stream must not be
                    // touched by software gain). The master gain is stored in the ViewModel as a UI
                    // value and applied only when the Enhanced path is active.
                    if self.activePath == .pure {
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

// AudioDeviceModel.DeviceType.sortOrder lives in AudioEngineBridge+Devices.swift (used by the
// device-enumeration sort there).
