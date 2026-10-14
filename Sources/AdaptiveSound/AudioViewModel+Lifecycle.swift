import AVFoundation
import Foundation

// MARK: - AudioViewModel engine lifecycle (init / shutdown / stop)

/// Engine lifecycle and the stop/teardown sequence. Split out of `AudioViewModel.swift` to keep
/// that file under the file-length limit, matching the existing `AudioViewModel+*.swift`
/// extension-split convention. Behaviour is identical to the inlined versions; the ordered
/// shutdown teardown (P2-C) and the `performStop()` sequencing are preserved exactly.
extension AudioViewModel {
    // MARK: - Engine Lifecycle

    func initializeEngine() {
        // Idempotent, two ways (both race-free under `@MainActor`):
        //   • `!isInitializing` — a second init while one is in-flight races the retry's teardown
        //     over the same ARC class refs (retain-count corruption).
        //   • `!isEngineReady` — in resident mode, closing then REOPENING the window re-fires
        //     `ContentView.onAppear`; re-`initialize()`ing a live engine is the exact double-init
        //     the teardown ordering exists to prevent. `retryInitialization()` clears
        //     `isEngineReady` first, so a failed/lost engine still re-inits.
        guard !isInitializing, !isEngineReady else { return }
        isInitializing = true
        Task {
            // Reset on EVERY completion path (success, the `!success` early return, and any throw
            // incl. `enumerateOutputDevices`) so the guard can never get stuck latched `true`.
            defer { isInitializing = false }
            do {
                let success = try await engine.initialize()
                if !success {
                    logUX("initializeEngine: failed (engine returned false)")
                    errorMessage = "Failed to initialize audio engine"
                    isEngineReady = false
                    return
                }

                // Enumerate real output devices from CoreAudio, and show the one the engine starts
                // on (the system default). Starting on it is not the user's pick (founder decision,
                // R1): nothing is chosen until they pick, so the pin follows the default until then,
                // and a re-initialization keeps the device they did pick.
                let devices = try await engine.enumerateOutputDevices()
                showEngineOutput(among: devices)
                // Push the connect-behaviour preference so the engine acts on it from the first
                // device change (its default matches, but this keeps them explicitly in step).
                engine.setPinPlaybackToSelectedDevice(pinPlaybackToSelectedDevice)
                // Keep the picker current when devices connect/disconnect (e.g. Bluetooth).
                engine.onOutputDevicesChanged = { [weak self] in self?.refreshDevices() }
                isEngineReady = true
                // Launch publish (Sprint EQ engine-plan §5.4): the engine plays the Intensity,
                // crossfeed and Master Gain the UI shows from the first block, not its own defaults.
                publishPlaybackIntents()
                // Fire the ready hook the instant the AU is live (e.g. EQ re-dispatches its
                // restored "last setting" curve, which no-ops until now). This is the single
                // ready-transition site, so it also covers device-loss `retryInitialization`.
                onEngineReady?()
                errorMessage = nil
                logUX("initializeEngine: ready — \(availableDevices.count) device(s), "
                    + "selected='\(selectedDevice?.name ?? "none")'")
                startSpectrumTimer()
            } catch {
                logUX("initializeEngine: error — \(error.localizedDescription)")
                errorMessage = "Engine initialization failed: \(error.localizedDescription)"
                isEngineReady = false
            }
        }
    }

    // MARK: - Control intents → engine

    /// Hand the engine every playback control intent this view model owns — Intensity,
    /// crossfeed, Master Gain and the output's transport — at engine-ready (also after device-loss
    /// `retryInitialization`, which re-runs `initializeEngine`). The EQ publishes from
    /// `onEngineReady` (its own view model); after a re-allocation the Realizer republishes its
    /// canonical state itself.
    func publishPlaybackIntents() {
        publishIntensity()
        publishCrossfeed()
        publishMasterGain()
        publishOutputTransport()
    }

    /// Tell the engine which kind of output it plays on (founder decision 29: the EQ-only path's
    /// limiter ceiling follows it). Called whenever `selectedDevice` is set; the engine ignores a
    /// transport it already has.
    func publishOutputTransport() {
        engine.publishOutputTransport(selectedDevice?.transportType ?? 0)
    }

    /// Publish `intensity`, clamped with a LOCAL (never re-assigned — see `intensity`).
    /// Synchronous, off-RT control-plane call (borrows the AU under the leaf lock). No Task:
    /// publishIntensity has no suspension point, and an unstructured Task only risks applying an
    /// earlier value after a later one under rapid slider drags (S3 finding F4).
    func publishIntensity() {
        engine.publishIntensity(max(0, min(1, intensity)))
    }

    /// Publish the crossfeed state (On/Off and strength).
    func publishCrossfeed() {
        engine.publishCrossfeed(enabled: crossfeedEnabled, strength: crossfeedStrength)
    }

    /// AWAITABLE teardown. The terminate path (`AppDelegate.applicationShouldTerminate`) awaits
    /// this and only lets AppKit finish quitting once it returns, so the ordered teardown is
    /// GUARANTEED to complete before the process exits. It used to be fire-and-forget (an
    /// unawaited `Task` kicked off from `ContentView.onDisappear`), so at quit the process could
    /// die mid-teardown — losing the P2-C ordering it exists to guarantee (use-after-free of the
    /// C handles). Being `async` also lets callers sequence teardown deterministically.
    func shutdown() async {
        logUX("shutdown — was playing=\(isPlaying)")
        // S10.2 2c quit-flush: persist the now-playing cursor and write the FINAL queue snapshot
        // BEFORE `performStop()` zeroes `playbackPosition` — so a clean quit restores exactly where
        // you left off. Cancel any pending debounced mirror first (this write supersedes it). The
        // library peer's own teardown has already run (AppDelegate ordering), but its `store` is
        // still live here, so this last SQLite write lands.
        persistQueueCursor()
        queueMirrorTask?.cancel()
        await mirrorQueueNow()
        // Stop the spectrum timer FIRST so no further `tickSpectrum` is scheduled (it polls
        // the engine and could otherwise touch handles we're about to tear down).
        stopSpectrumTimer()
        // S3 F5: the library subsystem (FSEvents watcher, volume monitor, in-flight scan/reconcile)
        // now lives on the LibraryModel peer, whose `shutdown()` the app-lifecycle owner
        // (AppDelegate) awaits BEFORE this — so the store is already quiescent (no scan/reconcile
        // writes) by the time we free the C audio handles below. That preserves the P2-C ordering
        // the pre-F5 single-model shutdown enforced inline here.
        // P2-C: ordered teardown — `engine.shutdown()` runs only AFTER `performStop()` has fully
        // completed, so shutdown can't tear down the engine/the loudness meter/the Pure session while
        // `stopAudio()` is still mid-flight on another thread → use-after-free of the C handles.
        // Close the play-verb gate FIRST (break-it): during the two awaits below, a play from
        // the menu bar / Control Center could pass the `isEngineReady` guard and land on
        // engineQueue AFTER the teardown block → "engine not initialized" at quit.
        isEngineReady = false
        await performStop()
        do {
            try await engine.shutdown()
        } catch {
            errorMessage = "Engine shutdown failed: \(error.localizedDescription)"
        }
        logUX("shutdown — complete")
    }

    // MARK: - Stop / teardown

    func stopPlayback() {
        logUX("stop (was at \(secs(playbackPosition))s)")
        // Clear the on-deck state synchronously so `tickSpectrum` won't react after stop.
        pendingNextIndex = nil
        // An explicit stop is not a pause: drop any position-preserving resume point so the next
        // Play starts from the top (D2).
        resumePoint = nil
        // Fire-and-forget for the normal (non-shutdown) stop path — behaviour unchanged.
        // The actual stop sequence lives in `performStop()` so `shutdown()` can `await` it.
        Task { await performStop() }
    }

    /// Stop the engine WITHOUT resetting the playhead — the position-preserving Pause path (D2).
    /// Mirrors `performStop()` but leaves `playbackPosition` and `duration` intact so the scrubber
    /// stays at the paused spot; `pause()` has already recorded `pausedResumePosition` for resume.
    func performPause() async {
        do {
            let epoch = nextStopEpoch()
            await engine.setNextTrack(nil, ticket: nextOnDeckTicket())
            try await engine.stopAudio(epoch: epoch)
            isPlaying = false
        } catch {
            errorMessage = "Pause failed: \(error.localizedDescription)"
        }
    }

    /// Stop the engine and reset transport state. Returns only once `stopAudio()` has fully
    /// completed, so callers that must tear the engine down afterwards (e.g. `shutdown()`) can
    /// `await` this to guarantee ordering and avoid a use-after-free of the C handles (P2-C).
    func performStop() async {
        do {
            let epoch = nextStopEpoch()
            await engine.setNextTrack(nil, ticket: nextOnDeckTicket())
            try await engine.stopAudio(epoch: epoch)
            isPlaying = false
            playbackPosition = 0
            duration = 0
            // Stop from an ALREADY-paused state is an `isPlaying` self-assign → its didSet's
            // `!= oldValue` guard suppresses the Now Playing hook, so Control Center would keep
            // showing the paused track. Fire explicitly so the clear rule runs (S10.4 QA #2).
            onNowPlayingRefresh?()
        } catch {
            errorMessage = "Stop playback failed: \(error.localizedDescription)"
        }
    }
}
