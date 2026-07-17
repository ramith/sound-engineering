// GlowFieldSpec — geometry + falloff data for the ambient content glows, and the pure
// visibility resolver (S10.7 PR 2, design §3.3). Pure data/functions per the Kit charter;
// the app-side `GlowField` view (Regime C decoration) renders from this and nothing else,
// and the R4 geometric audit samples the SAME data — tuning a center re-verifies the audit
// automatically.

import Foundation

// MARK: - Spec

public enum GlowFieldSpec {
    /// One ambient glow: its color pair and its geometry in UNIT space (center anchor as a
    /// fraction of the container; ellipse sizes in points from the 8a spec).
    public struct Glow: Sendable, Equatable {
        public let color: AppearancePair
        public let width: Double
        public let height: Double
        public let unitCenterX: Double
        public let unitCenterY: Double

        public init(color: AppearancePair, width: Double, height: Double,
                    unitCenterX: Double, unitCenterY: Double) {
            self.color = color
            self.width = width
            self.height = height
            self.unitCenterX = unitCenterX
            self.unitCenterY = unitCenterY
        }
    }

    /// The three 8a glows, centers DERIVED FROM THE MOCK'S CSS (PR-2 design review: the
    /// mock's radial-gradient offsets on its 1120×720 card, translated into tab space —
    /// blue is an INTERIOR midfield glow at ~0.63/0.62, not an edge bleed). Order is render
    /// order (teal under lime under blue). Founder-tunable in the by-eye rounds; the R4
    /// geometric audit re-runs against whatever lands here.
    /// PR-6 forward note: when the shell bands go glass, the field migrates to a
    /// shell-level mount; the equivalent WINDOW-space centers are teal (0.214, 0.139),
    /// lime (0.786, 0.889), blue (0.634, 0.597).
    public static let glows: [Glow] = [
        Glow(color: Palette.glowTeal, width: 720, height: 560, unitCenterX: 0.214, unitCenterY: 0.067),
        Glow(color: Palette.glowLime, width: 760, height: 600, unitCenterX: 0.786, unitCenterY: 0.973),
        Glow(color: Palette.glowBlue, width: 420, height: 380, unitCenterX: 0.634, unitCenterY: 0.621),
    ]

    /// The falloff profile — EXACT-LINEAR to match the mock's CSS `radial-gradient(
    /// closest-side, peak → 0)` (PR-2 design review: the blur pass only rounds the apex;
    /// the mid-field is a linear ramp, NOT a plateau): peak at center, `midAlphaFactor`
    /// of peak at `midStop`, clear at the edge — with 0.45 @ 0.55 both segments slope −1.
    public static let falloffMidStop: Double = 0.55
    public static let falloffMidAlphaFactor: Double = 0.45

    /// Fraction of peak alpha at normalized elliptical distance `t` ∈ [0, ∞) from a glow's
    /// center (t = 1 is the ellipse edge). The single profile source: the render gradient's
    /// stops AND the R4 geometric audit both read this.
    public static func falloffFraction(at t: Double) -> Double {
        if t <= 0 { return 1 }
        if t >= 1 { return 0 }
        if t <= falloffMidStop {
            return 1 - (1 - falloffMidAlphaFactor) * (t / falloffMidStop)
        }
        return falloffMidAlphaFactor * (1 - (t - falloffMidStop) / (1 - falloffMidStop))
    }

    /// Seam feather (points): the glow fades to nothing over this run at the top/bottom
    /// edges so the flat chrome/footer bands don't meet a lit field across a 0.5pt hairline
    /// (PR-2 review MAJOR 6: up to ΔRGB +39 otherwise). STOPGAP — removed in PR 6 when the
    /// bands go glass and the field migrates to a shell-level mount.
    public static let seamFeather: Double = 24

    /// The composite glow color at a unit point in a container of the given size:
    /// every glow's falloff-attenuated color folded over the window base, in render order.
    /// This is the function the R4 geometric audit samples.
    public static func compositeBackdrop(unitX: Double, unitY: Double,
                                         containerWidth: Double, containerHeight: Double,
                                         appearance: TokenAppearance) -> RGBAColor {
        var backdrop = Palette.window.value(for: appearance)
        let pointX = unitX * containerWidth
        let pointY = unitY * containerHeight
        for glow in glows {
            let deltaX = (pointX - glow.unitCenterX * containerWidth) / (glow.width / 2)
            let deltaY = (pointY - glow.unitCenterY * containerHeight) / (glow.height / 2)
            let t = (deltaX * deltaX + deltaY * deltaY).squareRoot()
            let fraction = falloffFraction(at: t)
            guard fraction > 0 else { continue }
            let color = glow.color.value(for: appearance)
            backdrop = color.opacity(color.alpha * fraction).over(backdrop)
        }
        return backdrop
    }

    /// Normalized elliptical distance from the TEAL glow's center at a unit point — the
    /// tertiary placement rule's geometry (§3.3: labelTertiary never inside the teal CORE,
    /// core = t ≤ falloffMidStop).
    public static func tealDistance(unitX: Double, unitY: Double,
                                    containerWidth: Double, containerHeight: Double) -> Double {
        let teal = glows[0]
        let deltaX = (unitX * containerWidth - teal.unitCenterX * containerWidth) / (teal.width / 2)
        let deltaY = (unitY * containerHeight - teal.unitCenterY * containerHeight) / (teal.height / 2)
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }
}

// MARK: - Visibility resolver (RES-04)

/// The glow field renders ONLY in dark appearance (PR 2): the 8a mock is dark-only, and the
/// review math shows any mid-luminance hue alpha-composited over the near-white light window
/// DARKENS it — a stain, unfixable by alpha choice. Light-mode ambience needs re-derived
/// luminance-positive pastels (S10.8 / D8 material). And it is TRANSLUCENCY DECORATION:
/// suppressed whenever the user asks for reduced transparency — including under Increase
/// Contrast alone (RES-02 doctrine: never depend on the OS coupling IC→RT).
public func glowFieldIsVisible(appearance: TokenAppearance,
                               reduceTransparency: Bool,
                               increasedContrast: Bool) -> Bool {
    appearance == .dark && !reduceTransparency && !increasedContrast
}
