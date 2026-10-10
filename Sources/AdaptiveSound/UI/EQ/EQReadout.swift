import EQEditKit
import Foundation

// MARK: - EQ readout wording (Sprint EQ, EQ3 — ui-plan §4.3, §5.4)

/// How the EQ graph names a band, on screen and to VoiceOver — one home, so the drag tag, the keyboard
/// readout and the 31 VoiceOver points always agree. Levels are the kit's `EQLevelText`, which the Tone
/// card and its readout write with too.
enum EQReadout {
    /// How far the played level must stray from the set one before VoiceOver adds "plays …" (dB).
    private static let playsDifferenceDb: Float = 0.2

    /// "31.5 Hz", "1 kHz", "12.5 kHz".
    static func frequency(_ hz: Double) -> String {
        hz >= 1000
            ? (hz / 1000).formatted(.number.precision(.fractionLength(0 ... 2))) + " kHz"
            : hz.formatted(.number.precision(.fractionLength(0 ... 1))) + " Hz"
    }

    /// The point readout (the drag tag and the keyboard strip): "1 kHz · set +4.0 dB · plays +3.9 dB",
    /// ending "· limited" while the ceiling holds the point.
    static func point(band: Int, set: Float, plays: Float?, limited: Bool) -> String {
        var parts = [frequency(EQBands.nominalHz[band]), "set " + EQLevelText.level(set)]
        if let plays {
            parts.append("plays " + EQLevelText.level(plays))
        }
        if limited {
            parts.append("limited")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: VoiceOver (words, never "kHz" or "dB", which VoiceOver spells out)

    /// "1 kilohertz", "31.5 hertz".
    static func spokenFrequency(_ hz: Double) -> String {
        hz >= 1000
            ? (hz / 1000).formatted(.number.precision(.fractionLength(0 ... 2))) + " kilohertz"
            : hz.formatted(.number.precision(.fractionLength(0 ... 1))) + " hertz"
    }

    /// The graph's VoiceOver value: the preset as it plays ("Warm, edited"), or what silences it.
    @MainActor
    static func spokenState(of eq: EQViewModel) -> String {
        switch eq.audible {
        case .playing, .engineNotReady:
            eq.isEdited ? "\(eq.current.preset.displayName), edited" : eq.current.preset.displayName
        case .off: "Off"
        case .comparing: "Comparing"
        case .pureMode: "Pure Mode"
        }
    }

    /// A point's VoiceOver value: its level, "plays …" only where the played level differs by 0.2 dB or
    /// more, and "limited" where the ceiling holds it.
    static func spokenPoint(set: Float, plays: Float?, limited: Bool) -> String {
        var parts = [EQLevelText.spoken(set)]
        if let plays, abs(plays - set) >= playsDifferenceDb {
            parts.append("plays " + EQLevelText.spoken(plays))
        }
        if limited {
            parts.append("limited")
        }
        return parts.joined(separator: ", ")
    }
}
