import EQEditKit
import Foundation

// MARK: - AudioViewModel Master Gain (S10.8 G, break-it G-GAIN-1)

/// Master Gain shows the level that plays (founder decision 2026-10-12, "Show the real level"). Off
/// Pure that is the app's own gain (`masterGain`), which the engine has from engine-ready on. On Pure
/// the bit-perfect stream is never scaled, so the one gain is the output device's own volume: the
/// slider shows what the device reads and sets the device when moved. Engaging Pure reads that
/// volume and never writes it — playing Pure must not make the device louder than it was.
extension AudioViewModel {
    /// What the Master Gain slider shows and moves right now.
    var masterGainControl: MasterGainControl {
        guard pureModeEngaged else { return .app(decibels: masterGain) }
        guard case let .decibels(shown) = signalPath.deviceVolume else { return .deviceFixed }
        // The knob holds the level asked for while the device still reads what it read right after:
        // a device can step its volume more coarsely than the slider, and the next key press must
        // still move on from where the knob is. Anything else moving the device (the volume keys)
        // changes the reading, and the knob follows the device again.
        let held = deviceVolumeRequest.flatMap { $0.answer == .decibels(shown) ? $0.decibels : nil }
        return .device(shown: shown, knob: held ?? shown)
    }

    /// The slider moved to `position`: set the app's gain, or on Pure the device's own volume.
    func setMasterGain(position: Float) {
        let level = MasterGainLaw.decibels(position: position)
        guard pureModeEngaged else {
            if masterGain != level {
                masterGain = level
            }
            return
        }
        guard let answer = engine.setDeviceVolume(decibels: level) else { return }
        deviceVolumeRequest = DeviceVolumeRequest(decibels: level, answer: answer)
        // The readout shows the device's answer now rather than at the next 20 Hz poll (which then
        // reads the same answer from the engine's snapshot).
        if signalPath.deviceVolume != answer {
            signalPath.deviceVolume = answer
        }
        if case let .decibels(reading) = answer {
            logMasterGain("device volume → \(MasterGainLaw.text(reading)) (Pure)")
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
    /// Pure, on a device with its own volume: what the device reads (`shown`) and where the knob
    /// sits (`knob`), both in dB on the device's scale.
    case device(shown: Float, knob: Float)
    /// Pure, on a device with no volume the app can set.
    case deviceFixed

    /// The readout: the level that plays ("-3.0 dB", "Silent"), or where it is set.
    var readout: String {
        switch self {
        case let .app(decibels): MasterGainLaw.text(decibels)
        case let .device(shown, _): MasterGainLaw.text(shown)
        case .deviceFixed: "Set on device"
        }
    }

    /// What VoiceOver says for the value.
    var spoken: String {
        switch self {
        case let .app(decibels): MasterGainLaw.spoken(decibels)
        case let .device(shown, _): MasterGainLaw.spoken(shown) + ", output device volume"
        case .deviceFixed: "set on the output device"
        }
    }

    /// Where the knob sits on the slider's travel.
    var position: Float {
        switch self {
        case let .app(decibels): MasterGainLaw.position(decibels: decibels)
        case let .device(_, knob): MasterGainLaw.position(decibels: knob)
        case .deviceFixed: 1 // nothing applied in the app: the top
        }
    }

    /// Whether moving the slider changes anything.
    var isAdjustable: Bool {
        self != .deviceFixed
    }

    /// The tooltip: what the slider controls when that isn't the app's own gain.
    var help: String {
        switch self {
        case .app: ""
        case .device: "Pure Mode plays the file untouched, so Master Gain sets your output device's own volume."
        case .deviceFixed:
            "Pure Mode plays the file untouched, and this output has no volume the app can set. "
                + "Use the device's own volume control."
        }
    }
}

/// A level the user set on the output device while Pure plays, and what the device read back.
struct DeviceVolumeRequest: Equatable {
    let decibels: Float
    let answer: DeviceVolume
}
