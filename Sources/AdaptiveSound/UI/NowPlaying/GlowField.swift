import DesignTokenKit
import SwiftUI

// MARK: - Glow Field (S10.7 PR 2 — design §3.3)

/// The ambient content glows behind the Now Playing tab — the light the glass-look panels
/// visibly sit over (Regime C decoration). Rendered ENTIRELY from `GlowFieldSpec` Kit data:
/// three shapes whose falloff is authored in radial-gradient stops reading the SAME
/// `falloffFraction` profile the R4 geometric audit samples (exact-linear, matching the 8a
/// mock's CSS `radial-gradient(closest-side, peak → 0)` — no `.blur`, zero filter passes).
///
/// Mounted via `.background { }` (never as a layout sibling — a ~760pt ellipse would inflate
/// the tab's ideal size). Decoration contract: hit-transparent, invisible to accessibility,
/// static, dark-appearance-only, and suppressed under Reduce Transparency / Increase
/// Contrast — all via the pure `glowFieldIsVisible` resolver behind `GlowFieldGate` (RES-04).
struct GlowField: View {
    /// D8 (PR 7): per-slot sampled-palette overrides — a nil slot (or nil array) keeps the
    /// brand token. Every entry is CLAMPED by the Kit (`SampledGlow`), so whatever arrives
    /// here is audit-admissible by construction; the render fold and the R4-GLOW-D8 audit
    /// fold share the override convention.
    var sampledPalette: [RGBAColor?]?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The window base always paints (AppShell's background is the same token; painting it
        // here too keeps the field self-contained wherever it's mounted).
        DesignSystem.Color.window
            .overlay {
                GlowFieldGate {
                    GeometryReader { geo in
                        ForEach(0 ..< GlowFieldSpec.glows.count, id: \.self) { index in
                            GlowEllipse(glow: GlowFieldSpec.glows[index],
                                        override: overrideColor(at: index),
                                        container: geo.size)
                                .position(
                                    x: geo.size.width * GlowFieldSpec.glows[index].unitCenterX,
                                    y: geo.size.height * GlowFieldSpec.glows[index].unitCenterY
                                )
                        }
                    }
                    // Seam feather (PR-2 review MAJOR 6, stopgap until PR 6 glasses the
                    // bands): fade the field out over the top/bottom edge runs so the flat
                    // chrome/footer never meet a lit pixel across a 0.5pt hairline.
                    .mask(seamFeatherMask)
                    // D8 recolor on track change is a DISCRETE restyle: one crossfade,
                    // gated on Reduce Motion (→ a cut) — never a continuous animation (§3.3).
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6),
                               value: sampledPalette)
                }
            }
            .clipped() // ellipses deliberately bleed past the edges; never paint outside
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func overrideColor(at index: Int) -> RGBAColor? {
        guard let sampledPalette, index < sampledPalette.count else { return nil }
        return sampledPalette[index]
    }

    private var seamFeatherMask: some View {
        GeometryReader { geo in
            let feather = CGFloat(GlowFieldSpec.seamFeather)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: feather / max(geo.size.height, 1)),
                    .init(color: .black, location: 1 - feather / max(geo.size.height, 1)),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - One glow

private struct GlowEllipse: View {
    let glow: GlowFieldSpec.Glow
    /// D8: the clamped sampled color for this slot (carries its own token alpha), or nil
    /// for the brand token pair.
    let override: RGBAColor?
    let container: CGSize

    private var width: CGFloat {
        container.width * glow.unitWidth
    }

    private var height: CGFloat {
        container.height * glow.unitHeight
    }

    var body: some View {
        // A CIRCULAR gradient scaled into the spec ellipse (PR-2 review BLOCKER 1: a circular
        // gradient clipped by a non-circular Ellipse leaves a hard rim on the minor axis —
        // scaling the whole circle makes every gradient isoline the spec ellipse instead).
        Circle()
            .fill(radialFalloff)
            .frame(width: width, height: width)
            .scaleEffect(x: 1, y: width > 0 ? height / width : 1)
    }

    /// The shared exact-linear profile, expressed as gradient stops: peak →
    /// `falloffFraction(midStop)` at the mid stop → clear at the edge.
    private var radialFalloff: RadialGradient {
        let color = override.map { SwiftUI.Color(token: $0) } ?? DesignSystem.Color.from(glow.color)
        let midStop = GlowFieldSpec.falloffMidStop
        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: color, location: 0),
                .init(color: color.opacity(GlowFieldSpec.falloffFraction(at: midStop)),
                      location: midStop),
                .init(color: color.opacity(0), location: 1),
            ]),
            center: .center,
            startRadius: 0,
            endRadius: width / 2
        )
    }
}
