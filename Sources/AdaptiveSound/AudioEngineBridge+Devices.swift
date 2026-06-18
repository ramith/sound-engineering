import AVFoundation
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
            DispatchQueue.global().async {
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

    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // selectOutputDeviceC returns Int32: 1 = success, 0 = failure
                let result = selectOutputDeviceC(deviceID)
                if result != 0 {
                    // Track the selected device so Pure Mode can open the HAL engine on it.
                    self.currentDeviceID = deviceID
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
            DispatchQueue.main.async { self.onOutputDevicesChanged?() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block
        )
        if status == noErr {
            deviceListListenerBlock = block
        } else {
            NSLog("[AudioEngineBridge] failed to register device-list listener: \(status)")
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
            DispatchQueue.global(qos: .userInitiated), block
        )
        deviceListListenerBlock = nil
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
