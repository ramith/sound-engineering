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
    /// Returns real device IDs, UIDs, names, sample rates, transports and types — no mock data.
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
                    let modelUID = Self.deviceString(info.deviceID, copyOutputDeviceModelUIDC)
                    models.append(AudioDeviceModel(
                        id: info.deviceID,
                        name: name,
                        sampleRate: info.sampleRate,
                        bufferFrameSize: info.bufferFrameSize,
                        uid: Self.deviceString(info.deviceID, copyOutputDeviceUIDC),
                        modelUID: modelUID.isEmpty ? nil : modelUID,
                        transportType: info.transportType,
                        type: deviceType
                    ))
                }

                // Sort: built-in first, then wireless, then USB, then unknown.
                // Within each type, sort alphabetically by name.
                models.sort { lhs, rhs in
                    let lhsOrder = lhs.type.sortOrder
                    let rhsOrder = rhs.type.sortOrder
                    if lhsOrder != rhsOrder {
                        return lhsOrder < rhsOrder
                    }
                    return lhs.name < rhs.name
                }

                continuation.resume(returning: models)
            }
        }
    }

    /// Read one of the bridge's per-device strings (`copyOutputDeviceUIDC` /
    /// `copyOutputDeviceModelUIDC`) whole: the C call returns the full length snprintf-style, so a
    /// value longer than the first buffer is read again into one that fits. Empty when the device
    /// has none.
    private static func deviceString(
        _ deviceID: UInt32,
        _ copy: (UInt32, UnsafeMutablePointer<CChar>?, UInt32) -> UInt32
    ) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = Int(copy(deviceID, &buffer, UInt32(buffer.count)))
        if length >= buffer.count {
            buffer = [CChar](repeating: 0, count: length + 1)
            _ = copy(deviceID, &buffer, UInt32(buffer.count))
        }
        return String(utf8String: buffer) ?? ""
    }

    /// The device the engine currently targets — the app-selected device, or (at launch) the system
    /// default captured in `initialize()`. The view model selects the matching `AudioDeviceModel` on
    /// launch so the UI selection and the engine's `currentDeviceID` never diverge (a divergence broke
    /// the app-authority re-assert: it tried to re-pin a stale id and failed with "device gone").
    func currentOutputDeviceID() -> UInt32 {
        currentDeviceID
    }

    /// Make `deviceID` the device the app plays on (the pill). The target is set FIRST, then the
    /// system default: the default-output listener then finds the app's own change already
    /// matching its device, so the output rule neither fights it (pinned) nor re-adopts it
    /// (follow). Enhanced follows the new default through the configuration change; a playing Pure
    /// session is moved by the view model (`AudioViewModel.adoptOutput`).
    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                let previous = self.currentDeviceID
                self.setOutputTarget(deviceID)
                // selectOutputDeviceC returns Int32: 1 = success, 0 = failure
                let result = selectOutputDeviceC(deviceID)
                if result != 0 {
                    logUX("engine selectDevice: id=\(deviceID) result=ok")
                } else {
                    self.setOutputTarget(previous)
                    logUX("engine selectDevice: id=\(deviceID) result=failed")
                }
                continuation.resume(returning: result != 0)
            }
        }
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
