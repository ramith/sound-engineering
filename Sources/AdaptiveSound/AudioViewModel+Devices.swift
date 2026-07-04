import Foundation

// MARK: - AudioViewModel device management

extension AudioViewModel {
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

                selectedDevice = device
                sampleRate = device.sampleRate
                bufferFrameSize = device.bufferFrameSize
                errorMessage = nil
                logUX("selectDevice: ok '\(device.name)' id=\(device.id) "
                    + "\(device.displayKHz) buf=\(device.bufferFrameSize)")
                // QW-C: auto-disable crossfeed when switching to a non-headphone device.
                if crossfeedEnabled && !deviceIsHeadphones {
                    crossfeedEnabled = false
                    logUX("selectDevice: crossfeed auto-disabled (non-headphone device)")
                }
            } catch {
                logUX("selectDevice: error '\(device.name)' — \(error.localizedDescription)")
                errorMessage = "Device selection failed: \(error.localizedDescription)"
            }
        }
    }

    /// Re-enumerate output devices after the device set changes (connect/disconnect), preserving the
    /// current selection when it still exists. Invoked on the main actor via `onOutputDevicesChanged`.
    func refreshDevices() {
        Task {
            guard let devices = try? await engine.enumerateOutputDevices() else { return }
            availableDevices = devices
            // Reflect the engine's ACTUAL target after the connect-behaviour handler ran: PIN mode
            // re-pinned the selected device; FOLLOW mode adopted the newly-connected one. If that
            // target isn't listed, keep the current selection when still present, else fall to first.
            let engineDeviceID = engine.currentOutputDeviceID()
            if let target = devices.first(where: { $0.id == engineDeviceID }) {
                selectedDevice = target
            } else if !(selectedDevice.map { sel in devices.contains { $0.id == sel.id } } ?? false) {
                selectedDevice = devices.first
            }
            // QW-C: auto-disable crossfeed if the new selected device is not a headphone type.
            if crossfeedEnabled && !deviceIsHeadphones {
                crossfeedEnabled = false
                logUX("refreshDevices: crossfeed auto-disabled (non-headphone device)")
            }
            logUX("refreshDevices: \(devices.count) device(s) "
                + "[\(devices.map(\.name).joined(separator: " | "))] "
                + "selected='\(selectedDevice?.name ?? "none")'")
        }
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
