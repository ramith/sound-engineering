// GlowFieldSpec — geometry + falloff data for the ambient content glows, and the pure
// visibility resolver (S10.7 PR 2, design §3.3). Pure data/functions per the Kit charter;
// the app-side `GlowField` view (Regime C decoration) renders from this and nothing else.

import Foundation

// MARK: - Spec

public enum GlowFieldSpec {
    /// One ambient glow: its color pair and its geometry in UNIT space (center anchor as a
    /// fraction of the container; sizes in points from the 8a spec). Centers sit at/over the
    /// edges so the ellipses bleed off — the CSS original blurred hard shapes; we author the
    /// falloff in gradient stops instead (§3.3: zero filter passes).
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

    /// The three 8a glows: teal top-left, lime bottom-right, blue mid-right. Geometry is the
    /// 8a spec's ellipse sizes; centers are first-pass values the founder tunes in the PR-2
    /// by-eye (§8 stopping rule: two rounds, then freeze).
    public static let glows: [Glow] = [
        Glow(color: Palette.glowTeal, width: 720, height: 560, unitCenterX: 0.10, unitCenterY: 0.08),
        Glow(color: Palette.glowLime, width: 760, height: 600, unitCenterX: 0.92, unitCenterY: 0.95),
        Glow(color: Palette.glowBlue, width: 420, height: 380, unitCenterX: 1.02, unitCenterY: 0.45),
    ]

    /// Eased 3-stop falloff approximating the CSS blur (design §3.3): peak at the center,
    /// `midAlphaFactor` of peak at `midStop`, clear at the edge.
    public static let falloffMidStop: Double = 0.55
    public static let falloffMidAlphaFactor: Double = 0.35
}

// MARK: - Visibility resolver (RES-04)

/// The glow field is TRANSLUCENCY DECORATION: suppressed (flat window base) whenever the
/// user asks for reduced transparency — and under Increase Contrast even if the OS didn't
/// couple IC→RT for us (the RES-02 doctrine: never depend on the OS doing the coupling).
public func glowFieldIsVisible(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
    !reduceTransparency && !increasedContrast
}
