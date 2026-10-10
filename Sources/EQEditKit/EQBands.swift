// EQBands — the 31-band grid every EQ layer shares (Sprint EQ, EQ0). The band INDEX is the
// contract between the editor, the presets and the engine; frequencies are two views of it:
// the exact 1/3-octave centres the maths uses (the Tone weights), and the nominal ISO 266
// centres the UI labels and plots by, at which the built-in presets are voiced.

import Foundation

public enum EQBands {
    /// Number of bands, indexed 0…30 from 20 Hz to 20 kHz.
    public static let count = 31

    /// The ISO 266 nominal 1/3-octave centres (Hz): what the UI shows and plots, and the
    /// frequencies the built-in presets are evaluated at.
    public static let nominalHz: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
        2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
    ]

    /// The exact base-10 1/3-octave centres, f_m = 10^(1.3 + 0.1·m) (19.95 Hz … 19.95 kHz).
    /// The nominal list rounds these for display; the maths never does.
    static let centreHz: [Double] = (0 ..< count).map { pow(10, 1.3 + 0.1 * Double($0)) }

    /// The ±dB range of a point: what is drawn and what the engine is sent.
    static let pointLimitDb: Float = 12

    /// The ±dB range of the user's base layer. Wider than a point, so a point the user sets can
    /// land exactly under a Tone offset (base = point − Tone) without being cut short.
    static let baseLimitDb: Float = 24

    /// The ±dB range of each Tone region.
    static let toneLimitDb: Float = 12
}

extension Float {
    /// This value held inside ±`limit`.
    func clamped(within limit: Float) -> Float {
        min(max(self, -limit), limit)
    }
}
