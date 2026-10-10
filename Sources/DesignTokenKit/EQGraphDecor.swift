// EQGraphDecor — the EQ graph's washes as Kit data (Sprint EQ, EQ3; ui-plan §6): every translucent
// layer the curve and its beads sit on — the analyzer silhouette, a Tone region's shading, the active
// band's column and the played curve's area fill — DERIVED from existing tokens (light is frozen,
// decision 16: no new hue, only how strongly an audited one is laid down), so the R4-EQ audits
// composite exactly what the graph paints.
//
// The washes STACK (a Tone region shaded over the silhouette, under the column and the area fill), and
// R4-EQ-01 holds the curve and beads to 3:1 on the whole stack. That is what sets these strengths: the
// designer's prototype values (dark 11 / 14 / 8 / 13 %) measured 2.96:1 stacked at the glow's peak, and
// light measured lower still, so each wash gives a little.

import Foundation

public enum EQGraphDecor {
    /// The played curve's area fill, between the curve and 0 dB: `accentFill` at 12 % (dark) / 8 % (light).
    public static let curveArea = AppearancePair(light: Palette.accentFill.light.opacity(0.08),
                                                 dark: Palette.accentFill.dark.opacity(0.12))

    /// A Tone region's shading where its weight is 1 (scaled by the weight elsewhere): `accentFill` at
    /// 12 % (dark) / 8 % (light).
    public static let toneShade = AppearancePair(light: Palette.accentFill.light.opacity(0.08),
                                                 dark: Palette.accentFill.dark.opacity(0.12))

    /// The column of the band being dragged or under the keyboard cursor: `accentFill` at 7 % (dark) /
    /// 5 % (light).
    public static let activeColumn = AppearancePair(light: Palette.accentFill.light.opacity(0.05),
                                                    dark: Palette.accentFill.dark.opacity(0.07))

    /// The analyzer silhouette behind the curve: the analyzer's own ramp (`SpectrumRamp`) at 10 % (dark)
    /// / 6 % (light) — the music's shape, never louder than the curve on it.
    public static func silhouette(at position: Float) -> AppearancePair {
        let ramp = SpectrumRamp.color(at: position)
        return AppearancePair(light: ramp.light.opacity(0.06), dark: ramp.dark.opacity(0.10))
    }

    /// The silhouette's tallest reach, as a fraction of the plot's height (a full-scale analyzer bar).
    public static let silhouetteHeight: Double = 0.42
}
