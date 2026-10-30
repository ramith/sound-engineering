import EQEditKit

// MARK: - PureModeReason

/// Why Pure Mode isn't playing bit-perfect, or isn't playing at all — the ONE named reason (R1.1-A,
/// council C-34, C-33). The engine's reasons arrive as the codes `PureModeBridge.h` documents
/// (`init(code:)`, the C++ policy's `PureModeReason` order); one more is the engine's own: a Master Gain
/// cut on a device whose volume the app can't set (`waitsForMasterGain`). On `SignalPathInfo`, `nil`
/// means there is nothing to say: Pure isn't asked for, or it plays bit-perfect.
enum PureModeReason: Equatable, CaseIterable {
    /// Bluetooth or AirPlay re-encode below the HAL (code 2).
    case bluetooth
    /// A virtual or aggregate device (3).
    case virtualDevice
    /// The device can't run at the track's sample rate (4).
    case rateUnsupported
    /// The device stream's channel count is not the track's (5).
    case channelCountMismatch
    /// Pure plays, but the output holds fewer bits than the source (6, C-33).
    case notBitPerfect
    /// The device would not take Pure's format, or would not start (7).
    case deviceWouldNotStart
    /// No decoder that may run can read the file (8).
    case fileUnreadable
    /// Apple's decoder can't read the file, and FFmpeg is off (9, FD-3).
    case needsFFmpeg
    /// Master Gain is turned down and the device has no volume the app can set: Pure would play
    /// louder, so it waits (the engine's own reason — `MasterGainOnPure`).
    case waitsForMasterGain
    /// Master Gain asks for less than the device's own volume can give — a cut below its floor, or Silent
    /// on a device with no mute the app can set: Pure would play louder than Master Gain says, so it waits
    /// (the engine's own reason — `MasterGainOnPure`, H-1).
    case masterGainBelowDeviceRange

    /// The reason a code from the engine names: nil for 0 and 1 (Pure plays bit-perfect) and for a
    /// code this build doesn't know.
    init?(code: UInt8) {
        guard let reason = Self.byCode[code] else { return nil }
        self = reason
    }

    /// The engine's codes (`PureModeBridge.h`), each to its reason.
    private static let byCode: [UInt8: PureModeReason] = [
        2: .bluetooth, 3: .virtualDevice, 4: .rateUnsupported, 5: .channelCountMismatch, 6: .notBitPerfect,
        7: .deviceWouldNotStart, 8: .fileUnreadable, 9: .needsFFmpeg,
    ]

    /// Whether Pure plays anyway: only when the depth is the reason.
    var purePlays: Bool {
        self == .notBitPerfect
    }

    /// The few words beside the Now Playing badge (and what VoiceOver adds to the signal path).
    var note: String {
        switch self {
        case .bluetooth: "Pure off: Bluetooth"
        case .virtualDevice: "Pure off: virtual output"
        case .rateUnsupported: "Pure off: sample rate"
        case .channelCountMismatch: "Pure off: channels"
        case .notBitPerfect: "Not bit-perfect"
        case .deviceWouldNotStart: "Pure off: device refused"
        case .fileUnreadable: "Pure off: unreadable"
        case .needsFFmpeg: "Pure off: needs FFmpeg"
        case .waitsForMasterGain: "Pure waits: Master Gain"
        case .masterGainBelowDeviceRange: "Pure waits: device range"
        }
    }

    /// The sentence for Settings ▸ Pure Mode and the note's tooltip: what happened, and what plays. The
    /// depth and the level come from the signal path (`info`) and Master Gain.
    func detail(in info: SignalPathInfo, masterGain: Float) -> String {
        switch self {
        case .notBitPerfect:
            "This \(info.sourceBitDepth)-bit track plays through a \(info.bitDepth)-bit output, so "
                + (Self.dithers(info) ? "Pure Mode reduces it to \(info.bitDepth) bits with dither"
                    : "its lowest bits are dropped")
                + ": it plays untouched otherwise, but not bit-perfect."
        case .waitsForMasterGain:
            "Master Gain is turned down (\(MasterGainLaw.text(masterGain))), and this device has no volume the app "
                + "can set. Pure Mode plays at the device’s own volume, which would be louder, so it waits until "
                + "Master Gain is back at 0 dB."
        case .masterGainBelowDeviceRange:
            "Master Gain (\(MasterGainLaw.text(masterGain))) turns your device down further than its own volume "
                + "goes, so Pure Mode would play louder than Master Gain says. It waits, and Enhanced is playing."
        case .channelCountMismatch:
            // A surround file on a narrower output is folded to stereo (R1.1-B, US-R1F-08 item 6).
            info.fold.map {
                "This track has \($0.sourceChannels) channels and your output has \($0.outputChannels), so Enhanced "
                    + "plays it, folded to stereo."
            } ?? declined
        default:
            declined
        }
    }

    /// Whether Pure reduces the track to an integer word with TPDF dither (the engine's
    /// `ditherWhenConverting`, R1.1-A): an integer output narrower than 32 bits.
    private static func dithers(_ info: SignalPathInfo) -> Bool {
        !info.isFloat && info.bitDepth > 0 && info.bitDepth < 32
    }

    /// Why Pure declined, and that Enhanced plays — for the reasons that carry no numbers.
    private var declined: String {
        switch self {
        case .bluetooth:
            "Bluetooth re-encodes the sound on its way to your device, so it can’t be bit-perfect. Enhanced is playing."
        case .virtualDevice:
            "This output is a virtual or combined device, which can’t play bit-perfect. Enhanced is playing."
        case .rateUnsupported:
            "Your device can’t run at this track’s sample rate, so Enhanced is converting it."
        case .channelCountMismatch:
            "This track has a different number of channels than your device, so Enhanced is playing it."
        case .deviceWouldNotStart:
            "Your device wouldn’t start a bit-perfect stream for this track, so Enhanced is playing."
        case .fileUnreadable:
            "Pure Mode’s decoder can’t read this file, so Enhanced is playing it."
        case .needsFFmpeg:
            "macOS can’t read this file. With FFmpeg turned on (Settings ▸ Formats), Pure Mode may play it."
        case .notBitPerfect, .waitsForMasterGain, .masterGainBelowDeviceRange:
            "" // they carry numbers: `detail`
        }
    }
}
