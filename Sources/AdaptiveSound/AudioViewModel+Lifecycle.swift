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
        Task {
            do {
                let success = try await engine.initialize()
                if !success {
                    logUX("initializeEngine: failed (engine returned false)")
                    errorMessage = "Failed to initialize audio engine"
                    isEngineReady = false
                    return
                }

                // Enumerate real output devices from CoreAudio
                let devices = try await engine.enumerateOutputDevices()

                availableDevices = devices
                // Select the device that is ACTUALLY the engine's current target (the system default
                // captured at init), not blindly "first" — otherwise the UI selection and the
                // engine's currentDeviceID diverge, and the app-authority re-assert later tries to
                // re-pin a stale id ("device gone"). Fall back to first if the default isn't listed.
                let engineDeviceID = engine.currentOutputDeviceID()
                let chosen = devices.first { $0.id == engineDeviceID } ?? devices.first
                selectedDevice = chosen
                // Assert the chosen device so currentDeviceID == selectedDevice == system default
                // from the start. A valid default re-asserts to itself (no change); a stale/phantom
                // default is corrected to the chosen device.
                if let chosen {
                    _ = try? await engine.selectDevice(chosen.id)
                }
                // Push the connect-behaviour preference so the engine acts on it from the first
                // device change (its default matches, but this keeps them explicitly in step).
                engine.setPinPlaybackToSelectedDevice(pinPlaybackToSelectedDevice)
                // Keep the picker current when devices connect/disconnect (e.g. Bluetooth).
                engine.onOutputDevicesChanged = { [weak self] in self?.refreshDevices() }
                isEngineReady = true
                errorMessage = nil
                logUX("initializeEngine: ready — \(devices.count) device(s), "
                    + "selected='\(selectedDevice?.name ?? "none")'")
                startSpectrumTimer()
            } catch {
                logUX("initializeEngine: error — \(error.localizedDescription)")
                errorMessage = "Engine initialization failed: \(error.localizedDescription)"
                isEngineReady = false
            }
        }
    }

    /// AWAITABLE teardown. The terminate path (`AppDelegate.applicationShouldTerminate`) awaits
    /// this and only lets AppKit finish quitting once it returns, so the ordered teardown is
    /// GUARANTEED to complete before the process exits. It used to be fire-and-forget (an
    /// unawaited `Task` kicked off from `ContentView.onDisappear`), so at quit the process could
    /// die mid-teardown — losing the P2-C ordering it exists to guarantee (use-after-free of the
    /// C handles). Being `async` also lets callers sequence teardown deterministically.
    func shutdown() async {
        logUX("shutdown — was playing=\(isPlaying)")
        // Stop the spectrum timer FIRST so no further `tickSpectrum` is scheduled (it polls
        // the engine and could otherwise touch handles we're about to tear down).
        stopSpectrumTimer()
        // S8.4: stop the FSEvents watcher (ordered Stop→Invalidate→Release) and cancel any
        // in-flight reconcile / playlist-refresh / scan. The detached scan+reconcile observe
        // per-file cancellation and skip their sweeps, so nothing writes to `store` while the
        // engine is being torn down.
        libraryWatcher?.stop()
        for task in reconcileDebounce.values {
            task.cancel()
        }
        playlistRefreshTask?.cancel()
        scanTask?.cancel()
        // P2-C: ordered teardown — `engine.shutdown()` runs only AFTER `performStop()` has fully
        // completed, so shutdown can't tear down `avEngine`/`loudnessMeter`/`pureEngine` while
        // `stopAudio()` is still mid-flight on another thread → use-after-free of the C handles.
        await performStop()
        do {
            try await engine.shutdown()
        } catch {
            errorMessage = "Engine shutdown failed: \(error.localizedDescription)"
        }
        isEngineReady = false
        logUX("shutdown — complete")
    }

    // MARK: - Stop / teardown

    func stopPlayback() {
        logUX("stop (was at \(secs(playbackPosition))s)")
        // Clear the on-deck state synchronously so `tickSpectrum` won't react after stop.
        pendingNextIndex = nil
        // An explicit stop is not a pause: drop any position-preserving resume point so the next
        // Play starts from the top (D2).
        pausedResumePosition = nil
        // Fire-and-forget for the normal (non-shutdown) stop path — behaviour unchanged.
        // The actual stop sequence lives in `performStop()` so `shutdown()` can `await` it.
        Task { await performStop() }
    }

    /// Stop the engine WITHOUT resetting the playhead — the position-preserving Pause path (D2).
    /// Mirrors `performStop()` but leaves `playbackPosition` and `duration` intact so the scrubber
    /// stays at the paused spot; `pause()` has already recorded `pausedResumePosition` for resume.
    func performPause() async {
        do {
            await engine.setNextTrack(nil)
            try await engine.stopAudio()
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
            await engine.setNextTrack(nil)
            try await engine.stopAudio()
            isPlaying = false
            playbackPosition = 0
            duration = 0
        } catch {
            errorMessage = "Stop playback failed: \(error.localizedDescription)"
        }
    }
}
