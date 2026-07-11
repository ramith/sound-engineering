@preconcurrency import AVFoundation
import CoreAudio
import Foundation

// MARK: - AudioEngineBridge: Device Enumeration

/// Output-device enumeration + selection via the C-ABI CoreAudio bridge. Extracted from
/// `AudioEngineBridge.swift` into a same-module extension to keep the core class body focused as
/// the multichannel epic grows it. These methods use only the global C-ABI functions and
/// `AudioDeviceModel` — no private engine state — so a separate file is safe.
extension AudioEngineBridge {
    /// Enumerate output devices using the C-ABI bridge to CoreAudio.
    /// Returns real device IDs, names, sample rates, and types — no mock data.
    func enumerateOutputDevices() async throws -> [AudioDeviceModel] {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                let maxDevices = 32
                var buffer = [CDeviceInfo](repeating: CDeviceInfo(), count: maxDevices)
                let count = enumerateOutputDevicesC(&buffer, UInt32(maxDevices))

                var models: [AudioDeviceModel] = []
                models.reserveCapacity(Int(count))

                for index in 0 ..< Int(count) {
                    let info = buffer[index]
                    let name = withUnsafeBytes(of: info.name) { rawPtr -> String in
                        let ptr = rawPtr.bindMemory(to: CChar.self)
                        guard let base = ptr.baseAddress else { return "" }
                        return String(cString: base)
                    }
                    let deviceType = AudioDeviceModel.DeviceType(rawValue: info.deviceType)
                    models.append(AudioDeviceModel(
                        id: info.deviceID,
                        name: name,
                        sampleRate: info.sampleRate,
                        bufferFrameSize: info.bufferFrameSize,
                        type: deviceType
                    ))
                }

                // Sort: built-in first, then wireless, then USB, then unknown.
                // Within each type, sort alphabetically by name.
                models.sort { lhs, rhs in
                    let lhsOrder = lhs.type.sortOrder
                    let rhsOrder = rhs.type.sortOrder
                    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                    return lhs.name < rhs.name
                }

                continuation.resume(returning: models)
            }
        }
    }

    /// The device the engine currently targets — the app-selected device, or (at launch) the system
    /// default captured in `initialize()`. The view model selects the matching `AudioDeviceModel` on
    /// launch so the UI selection and the engine's `currentDeviceID` never diverge (a divergence broke
    /// the app-authority re-assert: it tried to re-pin a stale id and failed with "device gone").
    func currentOutputDeviceID() -> UInt32 {
        currentDeviceID
    }

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                // selectOutputDeviceC returns Int32: 1 = success, 0 = failure
                let result = selectOutputDeviceC(deviceID)
                if result != 0 {
                    // Track the selected device so Pure Mode can open the HAL engine on it.
                    self.setCurrentDeviceID(deviceID)
                    logUX("engine selectDevice: id=\(deviceID) result=ok")
                } else {
                    logUX("engine selectDevice: id=\(deviceID) result=failed")
                }
                continuation.resume(returning: result != 0)
            }
        }
    }

    // MARK: - Device-list change listener (picker stays current on connect/disconnect)

    /// Register a `kAudioHardwarePropertyDevices` listener so the output-device picker refreshes
    /// when devices are added/removed (e.g. Bluetooth connect/disconnect). Fires
    /// `onOutputDevicesChanged` on the main thread; the view model re-enumerates. Registered in
    /// `initialize()`, removed in `shutdown()`.
    func registerDeviceListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listenerQueue = DispatchQueue.global(qos: .userInitiated)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            // DIAGNOSTIC: confirms macOS actually notified us of a device-set change. If a BT
            // headphone connects and this does NOT log, the CoreAudio device set didn't change
            // (a reconnecting device whose object persisted) → the picker never re-enumerates.
            logUX("device-list listener FIRED (kAudioHardwarePropertyDevices changed); "
                + "default=\(getDefaultOutputDeviceID()) — re-enumerating picker")
            // Apply the connect-behaviour preference (pin vs follow) BEFORE refreshing the picker
            // (a connecting device can steal the system default — see handleDeviceSetChange).
            self.handleDeviceSetChange()
            DispatchQueue.main.async {
                // `DispatchQueue.main` runs on the main thread, which is the main actor's
                // executor; `assumeIsolated` proves that to the compiler so the @MainActor
                // `onOutputDevicesChanged` callback can be invoked with no extra hop/allocation.
                MainActor.assumeIsolated { self.onOutputDevicesChanged?() }
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block
        )
        if status == noErr {
            deviceListListenerBlock = block
            deviceListListenerQueue = listenerQueue // F5: remove on the EXACT queue we added on
        } else {
            NSLog("[AudioEngineBridge] failed to register device-list listener: \(status)")
        }
    }

    func setPinPlaybackToSelectedDevice(_ pin: Bool) {
        pinPlaybackToSelectedDevice = pin
    }

    /// React to the available-device set changing while we are actively playing the Enhanced path
    /// (e.g. a Bluetooth device connects and macOS makes IT the system default). Behaviour is the
    /// user's `pinPlaybackToSelectedDevice` preference:
    ///   • PIN (default): re-pin the app's selected device as the default so playback stays put —
    ///     fixes the reported "connect BT → output goes silent / strands off my device" bug.
    ///   • FOLLOW: adopt the newly-connected default as the target and re-establish playback on it.
    /// Either way the resulting state fires `AVAudioEngineConfigurationChange` (and we also drive a
    /// re-establish for FOLLOW, since some devices don't post it). Skipped under Pure (its hogged
    /// device + alive-listener own routing) and when idle. Runs on the device-list listener queue.
    func handleDeviceSetChange() {
        // Read enhancedPlayIntent under its owning queue (resampleQueue) for a consistent snapshot.
        // This method runs on the device-list listener queue — off resampleQueue — so the sync is
        // deadlock-safe.
        let intent = resampleQueue.sync { enhancedPlayIntent }
        let selectedDeviceID = currentDeviceID
        guard activePathKind != .pure, intent, selectedDeviceID != 0 else { return }
        let currentDefault = getDefaultOutputDeviceID()
        guard selectedDeviceID != currentDefault else { return } // already targeting the default

        if pinPlaybackToSelectedDevice {
            let reasserted = selectOutputDeviceC(selectedDeviceID) != 0
            logUX("device change: PIN — selected=\(selectedDeviceID) != default=\(currentDefault) → "
                + "re-assert \(reasserted ? "ok" : "failed (selected device gone?)")")
        } else {
            // FOLLOW: target the newly-connected default and re-establish playback on it.
            logUX("device change: FOLLOW — adopt default=\(currentDefault) (was \(selectedDeviceID))")
            setCurrentDeviceID(currentDefault)
            if let engine = avEngineRef {
                configChangeQueue.async { [weak self] in
                    self?.reestablishEnhancedAfterConfigChange(engine: engine)
                }
            }
        }
    }

    func unregisterDeviceListListener() {
        guard let block = deviceListListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address,
            deviceListListenerQueue ?? DispatchQueue.global(qos: .userInitiated), block // F5
        )
        deviceListListenerBlock = nil
        deviceListListenerQueue = nil
    }
}

// MARK: - AudioDeviceModel.DeviceType sort order

private extension AudioDeviceModel.DeviceType {
    var sortOrder: Int {
        switch self {
        case .builtin: return 0
        case .wireless: return 1
        case .usb: return 2
        case .unknown: return 3
        }
    }
}
