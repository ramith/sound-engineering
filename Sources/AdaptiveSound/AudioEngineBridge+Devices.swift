@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import OutputDeviceKit

// MARK: - AudioEngineBridge: Device Enumeration

/// Output-device enumeration + selection via the C-ABI CoreAudio bridge. Extracted from
/// `AudioEngineBridge.swift` into a same-module extension to keep the core class body focused as
/// the multichannel epic grows it. Beyond the global C-ABI functions and `AudioDeviceModel`, they
/// touch only the output devices (`outputSelection`), through its guarded accessors.
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
                        uid: Self.deviceUID(info.deviceID),
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

    /// A device's persistent UID (`kAudioDevicePropertyDeviceUID`): what the app remembers a device
    /// by, since its id can change across a reconnect. Empty when the device is gone or has none. A
    /// HAL read: off the main thread.
    static func deviceUID(_ deviceID: UInt32) -> String {
        deviceString(deviceID, copyOutputDeviceUIDC)
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

    /// The user picked `deviceID` in the device menu: the app plays on it, and "Keep playback on this
    /// device" holds it — by UID — from now on (`OutputDeviceSelection`). Only the user's picks come
    /// here; the device the app starts on and the output rule's own moves never do. The target and
    /// the choice are set FIRST, then the system default: the default-output listener then finds the
    /// app's own change already matching its device, so the output rule neither fights it (pinned)
    /// nor re-adopts it (follow). Enhanced follows the new default through the configuration change;
    /// a playing Pure session is moved by the view model (`AudioViewModel.adoptOutput`).
    func selectDevice(_ deviceID: UInt32) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            self.engineQueue.async {
                let uid = Self.deviceUID(deviceID)
                let pick = self.changeOutputSelection { $0.choose(deviceID, uid: uid) }
                // selectOutputDeviceC returns Int32: 1 = success, 0 = failure
                let result = selectOutputDeviceC(deviceID)
                if result != 0 {
                    logUX("engine selectDevice: id=\(deviceID) uid=\(uid) result=ok")
                } else {
                    // Only the pick is taken back: a move the output rule made meanwhile stays.
                    self.changeOutputSelection { $0.undo(pick) }
                    logUX("engine selectDevice: id=\(deviceID) result=failed")
                }
                continuation.resume(returning: result != 0)
            }
        }
    }

    /// See `AudioPlaybackEngine.restoreChosenOutput`. The choice goes back under the leaf lock; the
    /// output rule then runs on `configChangeQueue`, as for any device event, and adopts the chosen
    /// device if it is here (the pill follows through `onOutputDevicesChanged`). No HAL call here.
    func restoreChosenOutput(uid: String?) {
        changeOutputSelection { $0.restoreChoice(uid: uid ?? "") }
        outputDeviceDidChange(.choiceRestored)
    }

    /// See `AudioPlaybackEngine.chosenOutputUID`.
    func chosenOutputUID() -> String? {
        let uid = outputSelection.chosenUID
        return uid.isEmpty ? nil : uid
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
