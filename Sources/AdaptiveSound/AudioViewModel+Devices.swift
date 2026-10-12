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

    /// The pill: make `device` the output the app plays on.
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
    /// went away, the engine adopted the system default (follow), or it paused for a lost device.
    /// Invoked on the main actor via `onOutputDevicesChanged`.
    func refreshDevices() {
        Task {
            guard let devices = try? await engine.enumerateOutputDevices() else { return }
            availableDevices = devices
            // The engine's device is the truth (the output rule pinned, re-asserted or adopted it).
            let engineDeviceID = engine.currentOutputDeviceID()
            if let target = devices.first(where: { $0.id == engineDeviceID }) {
                adoptOutput(target)
            } else {
                // Break-it MAJOR-1: the engine's target DIED (mid-play disconnect / PIN
                // re-assert failure). Keep a listed selection (or fall to the first device)
                // and PUSH it to the engine — otherwise the picker and engine diverge and
                // every Pure viability check runs against the corpse id (permanent "Pure
                // unavailable" until a manual re-pick). Converges: once re-asserted, the
                // engine target is listed again and this branch stops firing.
                if !(selectedDevice.map { sel in devices.contains { $0.id == sel.id } } ?? false) {
                    selectedDevice = devices.first
                }
                if let chosen = selectedDevice {
                    logUX("refreshDevices: engine target \(engineDeviceID) gone — re-asserting '\(chosen.name)'")
                    selectDevice(chosen)
                }
            }
            logUX("refreshDevices: \(devices.count) device(s) "
                + "[\(devices.map(\.name).joined(separator: " | "))] "
                + "selected='\(selectedDevice?.name ?? "none")'")
        }
    }

    /// Everything that follows the output the app plays on, in one place for the pill and the
    /// engine's own moves (follow, a lost device): the selection (its `didSet` re-keys the per-output
    /// EQ by UID and publishes the transport for the limiter ceiling), the rate and buffer readouts,
    /// the crossfeed headphone check, and — when Pure is playing — playback itself: the HAL engine
    /// is bound to its device, so it restarts on the new one at the playhead (Pure if that device
    /// allows it, else Enhanced). Enhanced follows the system default on its own.
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
        let path = engine.currentSignalPath()
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
