// EQLevelText — how the EQ writes a level (Sprint EQ; one home since EQ3t): the graph's point
// readouts, the Tone rows and the Tone readout all print "+4.0 dB" the same way, and VoiceOver hears
// "plus 4 decibels" for every one of them.

import Foundation

public enum EQLevelText {
    /// The level as a signed number to a tenth, no unit: "+4.0", "0.0", "-2.5" — the Tone rows' value
    /// column, whose unit is the slider's.
    public static func number(_ db: Float) -> String {
        tenths(db).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
    }

    /// The level with its unit: "+4.0 dB", "0.0 dB", "-2.5 dB".
    public static func level(_ db: Float) -> String {
        number(db) + " dB"
    }

    /// The level as VoiceOver speaks it — words, never "dB", which it spells out: "plus 4 decibels",
    /// "minus 2.5 decibels", "0 decibels".
    public static func spoken(_ db: Float) -> String {
        let rounded = tenths(db)
        let magnitude = abs(rounded).formatted(.number.precision(.fractionLength(0 ... 1))) + " decibels"
        if rounded > 0 {
            return "plus " + magnitude
        }
        return rounded < 0 ? "minus " + magnitude : magnitude
    }

    /// `db` to the tenth it prints at, with a level that rounds to zero made a plain 0 (never "-0.0").
    private static func tenths(_ db: Float) -> Float {
        let rounded = (db * 10).rounded() / 10
        return rounded == 0 ? 0 : rounded
    }
}
