import DesignTokenKit
import SwiftUI

// MARK: - Glow Field (S10.7 PR 2 — design §3.3)

/// The ambient content glows behind the Now Playing tab — the light the glass-look panels
/// visibly sit over (Regime C decoration). Rendered ENTIRELY from `GlowFieldSpec` Kit data:
/// three ellipses whose falloff is authored in 3-stop radial gradients (a gradient already IS
/// a smooth falloff — no `.blur`, zero filter passes under a 20 Hz-invalidating subtree).
///
/// Mounted via `.background { }` (never as a layout sibling — a ~760pt ellipse would inflate
/// the tab's ideal size). Decoration contract: hit-transparent, invisible to accessibility,
/// static (no motion), and suppressed to the flat window base under Reduce Transparency /
/// Increase Contrast (the pure `glowFieldIsVisible` resolver — RES-04).
struct GlowField: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        // The window base always paints (AppShell's background is the same token; painting it
        // here too keeps the field self-contained wherever it's mounted).
        DesignSystem.Color.window
            .overlay {
                if glowFieldIsVisible(reduceTransparency: reduceTransparency,
                                      increasedContrast: colorSchemeContrast == .increased) {
                    GeometryReader { geo in
                        ForEach(0 ..< GlowFieldSpec.glows.count, id: \.self) { index in
                            GlowEllipse(glow: GlowFieldSpec.glows[index])
                                .position(
                                    x: geo.size.width * GlowFieldSpec.glows[index].unitCenterX,
                                    y: geo.size.height * GlowFieldSpec.glows[index].unitCenterY
                                )
                        }
                    }
                }
            }
            .clipped() // ellipses deliberately bleed past the edges; never paint outside
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - One glow

private struct GlowEllipse: View {
    let glow: GlowFieldSpec.Glow

    var body: some View {
        Ellipse()
            .fill(radialFalloff)
            .frame(width: glow.width, height: glow.height)
    }

    /// The §3.3 falloff: peak → 35% of peak @ 0.55 → clear. Alpha rides the gradient stops;
    /// the base color (with the token's own appearance-resolved alpha) comes from the Kit.
    private var radialFalloff: RadialGradient {
        let color = DesignSystem.Color.from(glow.color)
        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: color, location: 0),
                .init(color: color.opacity(GlowFieldSpec.falloffMidAlphaFactor),
                      location: GlowFieldSpec.falloffMidStop),
                .init(color: color.opacity(0), location: 1),
            ]),
            center: .center,
            startRadius: 0,
            endRadius: max(glow.width, glow.height) / 2
        )
    }
}
