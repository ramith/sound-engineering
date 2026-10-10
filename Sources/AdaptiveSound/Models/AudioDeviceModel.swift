import EQEditKit
import Foundation

// MARK: - AudioDeviceModel

/// One output device as last read from CoreAudio.
///
/// Equality is SNAPSHOT equality: every field counts, so a view showing the device redraws when
/// its sample rate or buffer size changes. It is NOT the output's identity — the same output
/// re-read at a new rate is a different snapshot, and `id` is reassigned per session. Identity
/// is `uid`: ask "is this the same output?" through `outputKey` (`EQOutputKey.isOutputChange`),
/// which `AudioViewModel.onOutputIdentityChanged` fires on.
struct AudioDeviceModel: Identifiable, Equatable, Hashable {
    let id: UInt32
    let name: String
    let sampleRate: UInt32
    let bufferFrameSize: UInt32

    /// The device's persistent UID (`kAudioDevicePropertyDeviceUID`): the same output across
    /// reconnects and reboots. Empty only if CoreAudio reports none (every real output has one).
    let uid: String

    /// The device's model UID (`kAudioDevicePropertyModelUID`), shared by every unit of the same
    /// model; `nil` when the device reports none.
    let modelUID: String?

    /// The device's transport (`kAudioDevicePropertyTransportType` FourCC, e.g.
    /// `kAudioDeviceTransportTypeBluetooth`); 0 when unknown.
    let transportType: UInt32

    enum DeviceType: Hashable {
        case builtin
        case usb
        case wireless
        case unknown

        /// Map from the uint8_t sent by `CDeviceInfo.deviceType`.
        /// 0=Unknown, 1=Builtin, 2=USB, 3=Wireless (matches `AUAudioUnit.mm`).
        init(rawValue: UInt8) {
            switch rawValue {
            case 1: self = .builtin
            case 2: self = .usb
            case 3: self = .wireless
            default: self = .unknown
            }
        }
    }

    let type: DeviceType

    /// This output as the EQ keys it: by UID, with the model UID as the fallback and the name for
    /// display.
    var outputKey: EQOutputKey {
        EQOutputKey(uid: uid, modelUID: modelUID, name: name)
    }

    /// The transport as its four-character code ("blue", "bltn", "usb "), for logs; "none" when
    /// unknown.
    var transportCode: String {
        guard transportType != 0 else { return "none" }
        let bytes = withUnsafeBytes(of: transportType.bigEndian) { Array($0) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(transportType)
    }

    /// Returns the sample rate as a human-readable kHz string.
    /// Uses integer display when the rate is an exact multiple of 1000 Hz (e.g. "48 kHz"),
    /// and one decimal place otherwise (e.g. "44.1 kHz").
    var displayKHz: String {
        let khz = Double(sampleRate) / 1000.0
        if sampleRate % 1000 == 0 {
            return "\(sampleRate / 1000) kHz"
        }
        return String(format: "%.1f kHz", khz)
    }

    var displayName: String {
        let typeLabel: String
        switch type {
        case .builtin:
            typeLabel = "Built-in"
        case .usb:
            typeLabel = "USB"
        case .wireless:
            typeLabel = "Wireless"
        case .unknown:
            typeLabel = "Unknown"
        }
        return "\(name) (\(typeLabel))"
    }

    var systemIcon: String {
        switch type {
        case .builtin:
            return "speaker.wave.2.circle"
        case .usb:
            return "cable.connector"
        case .wireless:
            return "airpodspro"
        case .unknown:
            return "questionmark.circle"
        }
    }
}
