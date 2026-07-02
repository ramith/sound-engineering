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

    func shutdown() {
        logUX("shutdown — was playing=\(isPlaying)")
        // Stop the spectrum timer FIRST so no further `tickSpectrum` is scheduled (it polls
        // the engine and could otherwise touch handles we're about to tear down).
        stopSpectrumTimer()
        stopFolderMonitoring()
        // Cancel any in-flight library scan (mirrors folderMonitorDebounceTask): the
        // detached scan observes per-file cancellation and skips its sweep, so it never
        // writes to `store` while the engine is being torn down.
        scanTask?.cancel()
        // P2-C: sequence the teardown in a SINGLE ordered async chain so `engine.shutdown()`
        // runs only AFTER the stop has fully completed. Previously `stopPlayback()` spawned its
        // own (unawaited) Task while a separate Task called `engine.shutdown()`; the two were
        // unordered, so shutdown could tear down `avEngine`/`loudnessMeter`/`pureEngine` while
        // `stopAudio()` was still mid-flight on another thread → use-after-free of the C handles.
        Task {
            await performStop()
            do {
                try await engine.shutdown()
            } catch {
                errorMessage = "Engine shutdown failed: \(error.localizedDescription)"
            }
            isEngineReady = false
        }
    }

    // MARK: - Stop / teardown

    func stopPlayback() {
        logUX("stop (was at \(secs(playbackPosition))s)")
        // Clear the on-deck state synchronously so `tickSpectrum` won't react after stop.
        pendingNextIndex = nil
        // Fire-and-forget for the normal (non-shutdown) stop path — behaviour unchanged.
        // The actual stop sequence lives in `performStop()` so `shutdown()` can `await` it.
        Task { await performStop() }
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
