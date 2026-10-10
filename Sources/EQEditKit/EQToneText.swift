// EQToneText — the words for Tone levels (Sprint EQ, EQ3t): the Tone card's value column and
// VoiceOver value, the folded card's one line, and the level the graph's readout ends on
// ("Tone · Presence 2–6 kHz +3.0 dB"). In the kit so the copy is tested, and the card and the
// graph print a level the same way.

import Foundation

public enum EQToneText {
    /// A level as the readouts print it: "+3.0 dB", "-4.5 dB", "0 dB".
    public static func level(_ db: Float) -> String {
        isZero(db) ? "0 dB" : "\(signed(db)) dB"
    }

    /// A row's value column — narrow, so a set level drops the unit: "+3.0", "-4.5"; "0 dB" at 0.
    public static func value(_ db: Float) -> String {
        isZero(db) ? "0 dB" : signed(db)
    }

    /// A slider's VoiceOver value: "+3.0 decibels", "0 decibels", and ", limited" when the ceiling
    /// holds points the region reaches (`EQCurve.heldPointCount`).
    public static func spokenValue(_ db: Float, isLimited: Bool) -> String {
        let level = isZero(db) ? "0 decibels" : "\(signed(db)) decibels"
        return isLimited ? "\(level), limited" : level
    }

    /// The folded card's line: "all at 0 dB"; the one region set ("Presence +3.0 dB"); or how
    /// many are ("3 regions set") — the one line holds no more.
    public static func summary(of curve: EQCurve) -> String {
        let set = EQToneRegion.allCases.filter { curve.tone(of: $0) != 0 }
        switch set.count {
        case 0: return "all at 0 dB"
        case 1: return "\(set[0].name) \(level(curve.tone(of: set[0])))"
        default: return "\(set.count) regions set"
        }
    }

    /// A Tone step is 0.5 dB, so anything under half a tenth prints as 0.
    private static func isZero(_ db: Float) -> Bool {
        abs(db) < 0.05
    }

    private static func signed(_ db: Float) -> String {
        String(format: "%+.1f", db)
    }
}
