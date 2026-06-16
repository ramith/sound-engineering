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

    // MARK: - Graph state (scaffold for the multichannel reconfigure lifecycle; Sprint 5b)

    /// Top-level engine-graph state. Introduced in S0-M3; the `.reconfiguring` transition is now
    /// driven by `reconfigureGraph(to:)` (Sprint 5b M2-c). The trigger that calls it (track/device
    /// channel-count change) is wired in M2-d; nothing calls `reconfigureGraph` yet.
    enum GraphState {
        case idle
        case running(channelCount: Int)
        case reconfiguring
    }

    var graphState: GraphState = .idle

    // MARK: - Initialize

    func initialize() async throws -> Bool {
        // Register both custom AU subclasses once per process (idempotent on the C++ side).
        registerAdaptiveAudioUnitSubclass()
        registerSpatialRendererAUSubclass()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let engine = AVAudioEngine()
                self.avEngine = engine

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
                self.removeSpectrumTap()
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

    func startAudio(fileURL: URL? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    guard let engine = self.avEngine, let playerNode = self.playerNode else {
                        throw AudioBridgeError.engineNotInitialized
                    }

                    // Start the engine first
                    if !engine.isRunning {
                        try engine.start()
                    }

                    // Install the spectrum tap once the engine is running.
                    // installSpectrumTap is idempotent (guarded by tapInstalled flag).
                    self.installSpectrumTap()

                    if let fileURL = fileURL {
                        // Establish security-scoped access for sandboxed macOS file access
                        let didAccess = fileURL.startAccessingSecurityScopedResource()
                        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

                        // Load and schedule the audio file (AVAudioFile handles format conversion)
                        do {
                            // CRITICAL: Stop and reset the player before scheduling a new file.
                            // If we don't stop, the new file queues AFTER the old one instead of replacing it.
                            // This ensures track switching happens immediately, not after current track finishes.
                            if playerNode.isPlaying {
                                playerNode.stop()
                            }

                            let audioFile = try AVAudioFile(forReading: fileURL)
                            playerNode.scheduleFile(audioFile, at: nil)
                            playerNode.play()
                        } catch {
                            throw AudioBridgeError.unsupportedFormat(fileURL.pathExtension)
                        }
                    } else {
                        // Fallback to reference tone if no file provided
                        self.referenceToneBuffer = self.generateReferenceTone(
                            frequency: 1000.0,
                            duration: 5.0,
                            sampleRate: 48000.0
                        )

                        if let buffer = self.referenceToneBuffer {
                            if !playerNode.isPlaying {
                                playerNode.play()
                            }
                            playerNode.scheduleBuffer(buffer, at: nil)
                        }
                    }

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopAudio() async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if let playerNode = self.playerNode, playerNode.isPlaying {
                    playerNode.stop()
                }
                if let engine = self.avEngine, engine.isRunning {
                    engine.stop()
                }
                self.removeSpectrumTap()
                self.referenceToneBuffer = nil
                continuation.resume()
            }
        }
    }

    func currentPlaybackPosition() -> Double? {
        // Derive the playhead from the player node's render time. sampleTime counts
        // from 0 at play() and accumulates while playing — divide by the rate to get
        // seconds. AVAudioPlayerNode time queries are safe to call from any thread.
        guard let playerNode, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return nil
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    func setParameter(_ id: UInt32, value: Float) async throws {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                if id == 0 {
                    // Master gain parameter
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
