import EQEditKit
import Foundation
import OutputDeviceKit

// MARK: - AudioViewModel device management

extension AudioViewModel {
    /// `selectedDevice`'s `didSet`: fire `onOutputIdentityChanged` when the output itself changed
    /// (`EQOutputKey.isOutputChange` — by UID), never for a re-read of the same output.
    func announceOutputIdentityChange(from previous: AudioDeviceModel?) {
        let key = selectedDevice?.outputKey
        guard EQOutputKey.isOutputChange(from: previous?.outputKey, to: key) else { return }
        logUX("output identity → '\(key?.name ?? "none")' uid=\(key?.uid ?? "-") "
            + "model=\(key?.modelUID ?? "-") transport=\(selectedDevice?.transportCode ?? "-")")
        onOutputIdentityChanged?(key)
    }

    /// The pill: make `device` the output the app plays on — the user's pick, which "Keep playback on
    /// this device" holds from now on (the engine's `selectDevice`).
    func selectDevice(_ device: AudioDeviceModel) {
        logUX("selectDevice: '\(device.name)' id=\(device.id)")
        Task {
            do {
                let success = try await engine.selectDevice(device.id)
                if !success {
                    logUX("selectDevice: failed for '\(device.name)' id=\(device.id)")
                    errorMessage = "Failed to select device: \(device.name)"
                    return
                }
                errorMessage = nil
                logUX("selectDevice: ok '\(device.name)' id=\(device.id) "
                    + "\(device.displayKHz) buf=\(device.bufferFrameSize)")
                adoptOutput(device)
            } catch {
                logUX("selectDevice: error '\(device.name)' — \(error.localizedDescription)")
                errorMessage = "Device selection failed: \(error.localizedDescription)"
            }
        }
    }

    /// Re-read the devices and the engine's device after the output changed: a device connected or
    /// went away, the engine adopted a device (the system default, or the chosen device back), or it
    /// paused for a lost device. Invoked on the main actor via `onOutputDevicesChanged`.
    func refreshDevices() {
        Task {
            guard let devices = try? await engine.enumerateOutputDevices() else { return }
            availableDevices = devices
            // The engine's device is the truth: the output rule keeps it, or moves it. One that isn't
            // listed has just gone; the rule moves the engine off it (to the new default, or the
            // chosen device) and calls back, and until then no device shows. The view model never
            // picks a device itself (break-it MAJOR-1 used to): a pick is the user's, and the pin
            // holds it, so a fallback picked here would become the device Play returns to (N92).
            let engineDeviceID = engine.currentOutputDeviceID()
            if let target = devices.first(where: { $0.id == engineDeviceID }) {
                adoptOutput(target)
            } else {
                selectedDevice = nil
            }
            logUX("refreshDevices: \(devices.count) device(s) "
                + "[\(devices.map(\.name).joined(separator: " | "))] "
                + "engine=\(engineDeviceID) selected='\(selectedDevice?.name ?? "none")'")
        }
    }

    /// Everything that follows the output the app plays on, in one place for the pill and the
    /// engine's own moves (follow, a lost device, the chosen device back): the selection (its
    /// `didSet` re-keys the per-output EQ by UID and publishes the transport for the limiter
    /// ceiling), the rate and buffer readouts, the crossfeed headphone check, and — when Pure is
    /// playing — playback itself: the HAL engine is bound to its device, so it restarts on the new
    /// one at the playhead (Pure if that device allows it, else Enhanced). Enhanced follows the
    /// system default on its own.
    private func adoptOutput(_ device: AudioDeviceModel) {
        let moved = selectedDevice?.id != device.id
        selectedDevice = device
        sampleRate = device.sampleRate
        bufferFrameSize = device.bufferFrameSize
        // QW-C: auto-disable crossfeed when the output is not a headphone-class device.
        if crossfeedEnabled, !deviceIsHeadphones {
            crossfeedEnabled = false
            logUX("output: crossfeed auto-disabled (non-headphone device)")
        }
        guard moved else { return }
        let path = engine.snapshot().signalPath
        guard OutputDevicePolicy.playbackMovesWithOutput(
            isPlaying: isPlaying, onPure: path.path == .pure, interrupted: path.interrupted
        ) else { return }
        logUX("output moved while Pure plays — restarting on '\(device.name)' at \(secs(playbackPosition))s")
        startPlayback(resumeFrom: playbackPosition)
    }

    func retryInitialization() {
        // Bail if an init is already in-flight so retry can't clear state / re-enter under a
        // running init (`initializeEngine()` also guards and owns the `isInitializing` lifecycle).
        guard !isInitializing else { return }
        errorMessage = nil
        isEngineReady = false
        initializeEngine()
    }
}
