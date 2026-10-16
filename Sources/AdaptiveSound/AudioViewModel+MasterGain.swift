import EQEditKit
import Foundation

// MARK: - AudioViewModel Master Gain (S10.8 G, break-it G-GAIN-1; R1.1-A, C-29)

/// Master Gain is ONE level on both paths (founder decisions 2026-10-12, "Show the real level", and
/// 2026-10-15, "turn the Mac's volume down instead"). Off Pure the engine plays it as the app's own gain.
/// On Pure the bit-perfect stream is never scaled, so the engine turns the output device's own volume
/// down by it instead (`MasterGainOnPure`, EQEditKit): Pure engages at any Master Gain and the music is
/// as loud as it was; on a device with no volume the app can set, Pure waits while Master Gain is turned
/// down, and says why (`PureModeReason.waitsForMasterGain`). The view model only asks for Pure — the
/// engine knows the device. The loans of a device's volume not yet put back are kept with the listener's
/// settings (`pureVolumeLoans`), so a crash leaves no device turned down.
extension AudioViewModel {
    /// How the next start takes Pure, for the play log.
    var pureStartNote: String {
        pureModeEnabled ? "on (Master Gain \(MasterGainLaw.text(masterGain)))" : "off"
    }

    /// What the Master Gain slider shows and moves right now.
    var masterGainControl: MasterGainControl {
        guard pureModeEngaged else { return .app(decibels: masterGain) }
        return signalPath.deviceVolume == .fixed ? .deviceFixed : .pureDevice(decibels: masterGain)
    }

    /// The slider moved to `position`: Master Gain — the engine plays it in the app, or on Pure turns
    /// the device's own volume down by it (`publishMasterGain`, off the main thread).
    func setMasterGain(position: Float) {
        guard masterGainControl.isAdjustable else { return }
        let level = MasterGainLaw.decibels(position: position)
        if masterGain != level {
            masterGain = level
        }
    }

    /// Hand the engine the app's gain: on every change and at engine-ready
    /// (`publishPlaybackIntents`), so what plays from the first buffer is what the inspector shows.
    func publishMasterGain() {
        engine.publishMasterGain(decibels: masterGain)
    }

    /// Log a Master Gain line once per distinct line, so a drag doesn't log every tick.
    func logMasterGain(_ line: String) {
        guard line != lastMasterGainLogged else { return }
        logUX(line)
        lastMasterGainLogged = line
    }
}

// MARK: - What the slider shows

/// The Master Gain slider's state: whose level it is, what it reads, where the knob sits.
enum MasterGainControl: Equatable {
    /// Off Pure: the app's own gain, in dB.
    case app(decibels: Float)
    /// Pure, on a device with its own volume: Master Gain in dB, which the engine applies by turning
    /// the device's volume down.
    case pureDevice(decibels: Float)
    /// Pure, on a device with no volume the app can set (Pure engages there only at 0 dB).
    case deviceFixed

    /// The readout: the level ("-3.0 dB", "Silent"), or where it is set.
    var readout: String {
        switch self {
        case let .app(decibels), let .pureDevice(decibels): MasterGainLaw.text(decibels)
        case .deviceFixed: "Set on device"
        }
    }

    /// What VoiceOver says for the value.
    var spoken: String {
        switch self {
        case let .app(decibels): MasterGainLaw.spoken(decibels)
        case let .pureDevice(decibels): MasterGainLaw.spoken(decibels) + ", on the output device's volume"
        case .deviceFixed: "set on the output device"
        }
    }

    /// Where the knob sits on the slider's travel.
    var position: Float {
        switch self {
        case let .app(decibels), let .pureDevice(decibels): MasterGainLaw.position(decibels: decibels)
        case .deviceFixed: 1 // nothing applied in the app: the top
        }
    }

    /// Whether moving the slider changes anything.
    var isAdjustable: Bool {
        self != .deviceFixed
    }

    /// The tooltip: how Master Gain plays when that isn't the app's own gain.
    var help: String {
        switch self {
        case .app: ""
        case .pureDevice:
            "Pure Mode plays the file untouched, so Master Gain turns your output device’s own volume down instead."
        case .deviceFixed:
            "Pure Mode plays the file untouched, and this output has no volume the app can set. "
                + "Use the device’s own volume control."
        }
    }
}
