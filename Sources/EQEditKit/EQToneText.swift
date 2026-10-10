// EQToneText — the Tone's words (Sprint EQ, EQ3t): the graph's Tone readout, a Tone slider's VoiceOver
// value and the folded card's one line. In the kit so the copy is tested; levels are `EQLevelText`'s,
// so the card, the graph and VoiceOver write a level the same way.

import Foundation

public enum EQToneText {
    /// The graph's readout while a Tone slider is hovered or dragged: "Tone · Presence 2–6 kHz +3.0 dB",
    /// then "· 3 points held" when the ceiling holds points the region reaches.
    public static func readout(_ region: EQToneRegion, db: Float, heldPoints: Int) -> String {
        let readout = "Tone · \(region.name) \(region.span) \(EQLevelText.level(db))"
        switch heldPoints {
        case ...0: return readout
        case 1: return readout + " · 1 point held"
        default: return readout + " · \(heldPoints) points held"
        }
    }

    /// A Tone slider's VoiceOver value: "plus 3 decibels", ending ", limited" when the ceiling holds
    /// points the region reaches.
    public static func spokenValue(_ db: Float, isLimited: Bool) -> String {
        isLimited ? EQLevelText.spoken(db) + ", limited" : EQLevelText.spoken(db)
    }

    /// The folded card's line: "all at 0 dB"; the one region set ("Presence +3.0 dB"); or how many are
    /// ("3 regions set") — the one line holds no more.
    public static func summary(of curve: EQCurve) -> String {
        let set = EQToneRegion.allCases.filter { curve.tone(of: $0) != 0 }
        guard let first = set.first else { return "all at 0 dB" }
        guard set.count == 1 else { return "\(set.count) regions set" }
        return "\(first.name) \(EQLevelText.level(curve.tone(of: first)))"
    }
}
