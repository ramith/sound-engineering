// MasterGainLaw — the Master Gain's one law (S10.8 G; founder decision 2026-10-12, "Show the real
// level"): where the slider sits, the level in dB, and the linear gain that plays are one mapping,
// and the readout and VoiceOver write the level the way the EQ does (`EQLevelText`).
//
// Turn-down only: 0 dB at the top, never a boost (safest for hearing). The travel is dB-linear over
// 60 dB with a silent bottom stop — the "audio taper" a volume control needs because loudness is
// heard on a log scale: a slider linear in AMPLITUDE (the old one) puts the whole quiet half of the
// range in its bottom tenth and leaves the top half barely audible. Source: Dr. Lex, "Programming
// Volume Controls" (dr-lex.be/info-stuff/volumecontrols.html) — a volume slider should be
// exponential in amplitude (linear in dB), "a sensible assumption for consumer equipment is that it
// will have a usable range of 60 dB", the lowest position may simply be forced to silence, and
// discrete steps belong "between 1 dB and 3 dB".

import Foundation

public enum MasterGainLaw {
    /// The level at the top of the travel, and the default: unity, what plays before anyone touches
    /// the slider.
    public static let unity: Float = 0

    /// The level the travel spans down to: the quietest audible stop sits one step above it.
    public static let floorDecibels: Float = -60

    /// One step of the slider — a drag snaps to it and an arrow key or a VoiceOver swipe moves by
    /// it: 1 dB.
    public static let step: Float = 1 / 60

    /// The level at a slider position (0 … 1): 0 dB at the top, falling linearly in dB to the floor;
    /// the bottom stop (0) is silence, −∞ dB.
    public static func decibels(position: Float) -> Float {
        guard position > 0 else { return -.infinity }
        return floorDecibels * (1 - min(position, 1))
    }

    /// Where the slider sits for a level: the inverse of `decibels(position:)`. A level above
    /// 0 dB (a device's own volume can be) sits at the top; one at or below the floor, or silence,
    /// at the bottom stop.
    public static func position(decibels: Float) -> Float {
        guard isAudible(decibels) else { return 0 }
        return min(max(1 - decibels / floorDecibels, 0), 1)
    }

    /// The linear amplitude a level plays at: 10^(dB/20), never above unity (turn-down only), 0 for
    /// silence.
    public static func linearGain(decibels: Float) -> Float {
        guard isAudible(decibels) else { return 0 }
        return min(pow(10, decibels / 20), 1)
    }

    /// The readout: "0.0 dB", "-3.0 dB", "+2.0 dB" (a device's volume can sit above 0), or "Silent".
    public static func text(_ db: Float) -> String {
        isAudible(db) ? EQLevelText.level(db) : "Silent"
    }

    /// What VoiceOver says: "0 decibels", "minus 3 decibels", or "silent".
    public static func spoken(_ db: Float) -> String {
        isAudible(db) ? EQLevelText.spoken(db) : "silent"
    }

    /// Any real level; −∞ (the bottom stop) and NaN are silence — the safe reading of a bad value.
    private static func isAudible(_ db: Float) -> Bool {
        db > -.infinity
    }
}
