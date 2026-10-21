// DEV-UID (Sprint EQ) — the device-identity bridge against the LIVE CoreAudio device set. The
// EQ keys its per-output memory by device UID, so every enumerated output must report one, no
// two may share one, and the C copy contract must hold: the length query and the full copy agree,
// and a short buffer gets a NUL-terminated prefix. Prints each output's UID, model UID and
// transport (the default output marked). A machine with no output device has nothing to read and
// passes.

import AudioDSP
import Foundation

/// The C signature shared by `copyOutputDeviceUIDC` and `copyOutputDeviceModelUIDC`.
private typealias DeviceStringCopy = (UInt32, UnsafeMutablePointer<CChar>?, UInt32) -> UInt32

/// Read one device string through its C copy function, checking the contract on the way. `nil`
/// when the contract is broken.
private func readDeviceString(_ deviceID: UInt32, _ copy: DeviceStringCopy) -> String? {
    let length = Int(copy(deviceID, nil, 0))
    var full = [CChar](repeating: 0, count: length + 1)
    guard Int(copy(deviceID, &full, UInt32(full.count))) == length, full[length] == 0 else { return nil }
    var short = [CChar](repeating: 1, count: 4)
    guard Int(copy(deviceID, &short, UInt32(short.count))) == length else { return nil }
    let kept = min(length, short.count - 1)
    guard short[kept] == 0, short[..<kept].elementsEqual(full[..<kept]) else { return nil }
    return String(utf8String: full)
}

/// A CoreAudio FourCC ("blue", "bltn", "usb ") as text.
private func fourCC(_ code: UInt32) -> String {
    let bytes = withUnsafeBytes(of: code.bigEndian) { Array($0) }
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(code)
}

func verifyDeviceIdentity() -> Bool {
    print("--- DEV-UID device identity (UID / model UID / transport per output) ---")
    var infos = [CDeviceInfo](repeating: CDeviceInfo(), count: 32)
    let count = Int(enumerateOutputDevicesC(&infos, UInt32(infos.count)))
    guard count > 0 else {
        print("DEV-UID PASS: no output device on this machine — nothing to read")
        return true
    }
    let defaultID = getDefaultOutputDeviceID()
    var seenUIDs: Set<String> = []
    for info in infos.prefix(count) {
        let name = withUnsafeBytes(of: info.name) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) } ?? ""
        guard let uid = readDeviceString(info.deviceID, copyOutputDeviceUIDC),
              let modelUID = readDeviceString(info.deviceID, copyOutputDeviceModelUIDC)
        else {
            print("DEV-UID FAIL '\(name)': the copy contract is broken (length / NUL / truncation)")
            return false
        }
        guard !uid.isEmpty, seenUIDs.insert(uid).inserted else {
            print("DEV-UID FAIL '\(name)': UID \(uid.isEmpty ? "missing" : "'\(uid)' shared with another output")")
            return false
        }
        print("DEV-UID '\(name)'\(info.deviceID == defaultID ? " (default)" : ""): uid=\(uid) "
            + "model=\(modelUID.isEmpty ? "-" : modelUID) transport=\(fourCC(info.transportType))")
    }
    print("DEV-UID PASS: \(count) output(s), each with its own UID")
    return true
}
