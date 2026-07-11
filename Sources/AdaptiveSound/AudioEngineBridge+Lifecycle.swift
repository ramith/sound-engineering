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
                // LEAK #1 fix — teardown-before-reinit. `initialize()` has no external re-entry guard
                // and `AudioViewModel.retryInitialization()` can re-run it WITHOUT an intervening
                // `shutdown()`. Building a fresh graph + loudness meter over a live one would leak the
                // prior meter (and orphan the old AVAudioEngine graph + CoreAudio listeners). So if a
                // previous initialize already built the graph, run the SAME ordered teardown first
                // (removeSpectrumTap → meter wrapper dropped) so the rebuild starts from idle. This
                // matches the "create only when nil" discipline used for the Pure session. `avEngine`
                // is the "graph exists" sentinel (set below; cleared by the teardown); the guard is a
                // no-op on a fresh (idle) bridge.
                if self.avEngine != nil {
                    self.performEngineTeardown()
                }

                // Capture the current default output device so Pure Mode can open the right
                // HAL engine. Updated in selectDevice(_:) and by the device-change listener.
                self.setCurrentDeviceID(getDefaultOutputDeviceID())

                let engine = AVAudioEngine()
                self.setAvEngine(engine)
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
                self.setPlayerNode(player)
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
                self.performEngineTeardown()
                continuation.resume()
            }
        }
    }

    /// Ordered engine teardown, shared by `shutdown()` and the re-init guard in `initialize()`
    /// (LEAK #1). MUST run on `engineQueue`.
    ///
    /// Order is load-bearing:
    ///  1. Stop the streaming-resampler loop FIRST (bump generation + drop session) so no in-flight
    ///     buffer schedules onto the graph we're about to tear down.
    ///  2. Remove the CoreAudio property listeners before touching anything else.
    ///  3. `removeSpectrumTap()` BEFORE the loudness-meter wrapper is dropped — so no RT tap can hold
    ///     the meter's raw handle when its deinit destroys it (constraint: destroy only after
    ///     removeTap). The meter wrapper is dropped inside `resetGraphStateAfterShutdown`.
    ///  4. Stop/detach the active (Pure or Enhanced) engine + the shared two-AU graph.
    ///  5. Reset every field to its idle value (drops the meter wrapper — see step 3 ordering).
    private func performEngineTeardown() {
        stopEnhancedResampler()
        unregisterDeviceAliveListener()
        unregisterDeviceListListener()
        removeSpectrumTap()
        removeConfigChangeObserver()
        tearDownActiveEngine()
        resetGraphStateAfterShutdown()
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
        } else {
            // Orphaned session (e.g. failed mid-start; never reached .pure so tearDownPure's branch
            // was skipped): detach it (nils the field UNDER the lock) and let the returned wrapper
            // drop here on engineQueue — its deinit runs pureModeEngineDestroy OUTSIDE the lock,
            // releasing hog mode without blocking a concurrent poll. A no-op (returns nil, nothing
            // to drop) in the common case where there is no orphaned session.
            detachPureEngineForTeardown()
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
        setDspAudioUnit(nil)
        spatialAudioUnit = nil
        setAvEngine(nil)
        setPlayerNode(nil)
        referenceToneBuffer = nil
        spectrumAnalyzer = nil
        beforeAnalyzers = []
        afterAnalyzers = []
        setActivePath(.enhanced)
        storeSignalPath(.init())
        // Tap already removed above (removeSpectrumTap ran in shutdown before tearDownActiveEngine),
        // so no RT callback can still hold the meter's raw handle. Dropping the wrapper here runs its
        // deinit → loudnessMeterDestroy. This runs on engineQueue; the meter field is not stateLock-
        // guarded, so no lock ordering concern applies. Constraint: destroy ONLY after removeTap.
        loudnessMeter = nil
    }
}
