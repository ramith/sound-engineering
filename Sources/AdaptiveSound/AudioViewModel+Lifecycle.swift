import AVFoundation
import Foundation
import SettingsKit

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
        // The start holds the view model until it finishes; the callback it installs does not.
        work.spawn { [self] in
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

                // Keep the picker current when devices connect/disconnect (e.g. Bluetooth), or the
                // engine moves to the chosen device below.
                engine.onOutputDevicesChanged = { [weak self] in self?.refreshDevices() }
                // The connect behaviour, then the device the user chose — in this session, or before
                // the last quit (DEV-1). The engine starts on the system default, which is not the
                // user's pick (founder decision, R1): handing the choice back is not a pick either,
                // and the engine's output rule moves to it once it is here. Nothing chosen: the pin
                // follows the default until the user picks.
                engine.setPinPlaybackToSelectedDevice(pinPlaybackToSelectedDevice)
                engine.restoreChosenOutput(uid: chosenOutputUID)
                // Pure's device-volume loans live in their own journal, which the engine writes ahead of
                // every change (H-2): a device Pure turned down and never put back (the app died, or the
                // device went away mid-Pure) gets its level back, if it still reads what Pure set.
                engine.keepPureVolumeLoans(in: PureVolumeLoanJournal(defaults: defaults))
                // Enumerate real output devices from CoreAudio, and show the one the engine plays on.
                let devices = try await engine.enumerateOutputDevices()
                showEngineOutput(among: devices)
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
                armTransportTick()
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
    /// earlier value after a later one under rapid slider drags (S3 finding F4). The signal path
    /// carries it for the hero, so it is refreshed now — paused, no tick would.
    func publishIntensity() {
        engine.publishIntensity(max(0, min(1, intensity)))
        refreshSignalPathIntents()
    }

    /// Publish the crossfeed that plays (`crossfeedPlays`: chosen, on headphones) and its strength;
    /// the hero's "XF" chip reads it from the signal path, refreshed now — paused, no tick would.
    func publishCrossfeed() {
        engine.publishCrossfeed(enabled: crossfeedPlays, strength: crossfeedStrength)
        refreshSignalPathIntents()
    }

    /// AWAITABLE teardown. The terminate path (`AppDelegate.applicationShouldTerminate`) awaits
    /// this and only lets AppKit finish quitting once it returns, so the ordered teardown is
    /// GUARANTEED to complete before the process exits. It used to be fire-and-forget (an
    /// unawaited `Task` kicked off from `ContentView.onDisappear`), so at quit the process could
    /// die mid-teardown — losing the P2-C ordering it exists to guarantee (use-after-free of the
    /// C handles). Being `async` also lets callers sequence teardown deterministically.
    func shutdown() async {
        logUX("shutdown — was playing=\(isPlaying), commands in flight=\(!work.isIdle)")
        // The quit-flush: ask for one last write of the queue's resume record and wait for it BEFORE
        // `performStop()` zeroes `playbackPosition` — so a clean quit restores exactly where you left
        // off. The one writer writes as asked (no debounce to cancel). The library peer's own teardown
        // has already run (AppDelegate ordering), but its `store` is still live here, so this last
        // SQLite write lands.
        persistQueueCursor()
        settingsStore.flush() // a change made in the quit's own turn is written too
        await mirrorQueueNow()
        // Stop the transport tick FIRST so no further tick is scheduled (it polls the engine and could
        // otherwise touch handles we're about to tear down); disarmed, the stop below starts none.
        disarmTransportTick()
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
        await performStop(epoch: nextStopEpoch())
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
        // The stop takes the engine's on-deck with it.
        pendingNextIndex = nil
        // An explicit stop is not a pause: drop any position-preserving resume point so the next
        // Play starts from the top (D2).
        resumePoint = nil
        // Numbered now (council C-15): a Play right after it is newer, and wins at the engine whatever
        // order the two reach it in. The stop itself lives in `performStop()` so `shutdown()` can
        // `await` it.
        let epoch = nextStopEpoch()
        work.spawn { [self] in await performStop(epoch: epoch) }
    }

    /// Stop the engine WITHOUT resetting the playhead — the position-preserving Pause path (D2), for
    /// the pause numbered `epoch`. Mirrors `performStop()` but leaves `playbackPosition` and `duration`
    /// intact so the scrubber stays at the paused spot; `pause()` has already recorded
    /// `pausedResumePosition` for resume.
    func performPause(epoch: UInt64) async {
        do {
            // A pause: on Pure the device keeps the volume Pure set (founder decision 2026-10-16).
            try await engine.stopAudio(epoch: epoch, pausing: true)
            // A Play asked since owns the transport: it plays on (the engine dropped this stop if it had
            // begun the Play first).
            guard finish(.stop(epoch)) else { return }
            isPlaying = false
        } catch {
            errorMessage = "Pause failed: \(error.localizedDescription)"
        }
    }

    /// Stop the engine and reset transport state, for the stop numbered `epoch` (`nextStopEpoch()`).
    /// One engine call: the stop takes the on-deck pick with it. Returns only once `stopAudio()` has
    /// fully completed, so callers that must tear the engine down afterwards (e.g. `shutdown()`) can
    /// `await` this to guarantee ordering and avoid a use-after-free of the C handles (P2-C).
    func performStop(epoch: UInt64) async {
        do {
            // Playback ends: Pure is left, and the device gets its own level back.
            try await engine.stopAudio(epoch: epoch, pausing: false)
            // A start asked since owns the transport (and its playhead and length): leave them to it.
            guard finish(.stop(epoch)) else { return }
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
