@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge engine lifecycle (initialize / shutdown)

/// Engine bring-up and teardown, split out of the main class body (F: keep AudioEngineBridge.swift —
/// which must hold all stored properties, since Swift extensions cannot — under the file-length
/// budget). Both run on `engineQueue`; `deinit` (which frees the leaf lock) stays on the main class
/// body because a `deinit` cannot live in an extension.
extension AudioEngineBridge {
    // MARK: - Initialize

    func initialize() async throws -> Bool {
        // Register both custom AU subclasses once per process (idempotent on the C++ side).
        registerAdaptiveAudioUnitSubclass()
        registerSpatialRendererAUSubclass()

        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                // Capture the current default output device so Pure Mode can open the right
                // HAL engine. Updated in selectDevice(_:) and by the device-change listener.
                self.setCurrentDeviceID(getDefaultOutputDeviceID())

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
                self.instantiateAndBuildGraph(engine: engine, player: player, format: format) { success in
                    // `Bool` is Sendable, so this @Sendable wrapper around the continuation's
                    // resume is race-free; it makes the sending-parameter conversion explicit.
                    continuation.resume(returning: success)
                }
            }
        }
    }

    // MARK: - Shutdown

    func shutdown() async throws {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                // Stop the streaming-resampler loop FIRST (bump generation + drop session) so no
                // in-flight buffer schedules onto the graph we're about to tear down.
                self.stopEnhancedResampler()

                // Remove CoreAudio property listeners before tearing down anything else.
                self.unregisterDeviceAliveListener()
                self.unregisterDeviceListListener()

                self.removeSpectrumTap()
                self.removeConfigChangeObserver()
                self.tearDownActiveEngine()
                self.resetGraphStateAfterShutdown()

                continuation.resume()
            }
        }
    }

    /// Remove the CoreAudio-configuration-change `NotificationCenter` observer, if any.
    private func removeConfigChangeObserver() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
    }

    /// Stop and release whichever engine (Pure or Enhanced) is currently live, then stop and
    /// detach the shared two-AU `AVAudioEngine` graph. Split out of `shutdown()` so each teardown
    /// concern (path-specific engine vs. the shared graph) reads as one step.
    private func tearDownActiveEngine() {
        // Stop + destroy the Pure-Mode engine if live (releases hog mode + device rate).
        if activePathKind == .pure {
            tearDownPure()
        } else if let engine = detachPureEngineForTeardown() {
            // Orphaned handle (e.g. failed mid-start): destroy OUTSIDE the lock (the detach
            // nils the field first) to avoid a hog leak without blocking a concurrent poll.
            pureModeEngineDestroy(engine)
        }

        if let playerNode = playerNode, playerNode.isPlaying {
            playerNode.stop()
        }
        if let engine = avEngine, engine.isRunning {
            engine.stop()
        }
        // Detach both AUs (graph is stopped; safe to mutate) and drop the strong refs.
        if let engine = avEngine {
            if let effectsUnit = dspAudioUnit { engine.detach(effectsUnit) }
            if let spatialUnit = spatialAudioUnit { engine.detach(spatialUnit) }
        }
    }

    /// Reset every stored field to its post-shutdown idle value and destroy the loudness meter.
    private func resetGraphStateAfterShutdown() {
        dspAudioUnit = nil
        spatialAudioUnit = nil
        avEngine = nil
        playerNode = nil
        referenceToneBuffer = nil
        spectrumAnalyzer = nil
        graphState = .idle
        beforeAnalyzers = []
        afterAnalyzers = []
        setActivePath(.enhanced)
        storeSignalPath(.init())
        // Tap already removed above, so no callback can touch the meter now.
        if let meter = loudnessMeter {
            loudnessMeterDestroy(meter)
            loudnessMeter = nil
        }
    }
}
