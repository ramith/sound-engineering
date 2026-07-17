// DesignSystemGlass — the SwiftUI half of the S10.7 token contract (design §3.2), and the
// future home of the `Glass` decoration namespace (roles land staged, each with its first
// consumer). Two jobs live here:
//
//   1. BRIDGE: `DesignTokenKit` holds every color as plain RGBA data (the single source —
//      testable, auditable); this file turns that data into SwiftUI values. No RGBA literal
//      may exist on this side — a value needed here is a value added to the Kit.
//   2. `.glassPanel(_:in:)`: the ONE place a surface material/fill is painted. Views say
//      what a surface IS (`SurfaceRole`); the environment→resolver→paint wiring here decides
//      how it looks. The semgrep layer-policy tripwires (PR 1b) hold every other UI file to
//      that contract.

import DesignTokenKit
import SwiftUI

// MARK: - Kit → SwiftUI color bridging

extension SwiftUI.Color {
    /// A Kit color, constructed in explicit sRGB (both the former `Color(white:)` and
    /// `Color(red:green:blue:)` token literals were sRGB, so this one path is exact for both).
    init(token: RGBAColor) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}

extension DesignSystem.Color {
    /// The re-export path for a Kit pair: appearance-independent pairs bridge to a plain
    /// color (matching the pre-Kit literals exactly); appearance-dependent pairs go through
    /// the dynamic provider, including the increased-contrast appearance names.
    static func from(_ pair: AppearancePair) -> SwiftUI.Color {
        let isAppearanceIndependent = pair.light == pair.dark
            && pair.lightHighContrast == pair.light && pair.darkHighContrast == pair.dark
        if isAppearanceIndependent { return SwiftUI.Color(token: pair.light) }
        return dynamic(light: SwiftUI.Color(token: pair.light),
                       dark: SwiftUI.Color(token: pair.dark),
                       lightHighContrast: SwiftUI.Color(token: pair.lightHighContrast),
                       darkHighContrast: SwiftUI.Color(token: pair.darkHighContrast))
    }
}

// MARK: - .glassPanel(_:in:)

extension View {
    /// Declare a surface's ROLE; this modifier (via the Kit's pure resolver) owns how the
    /// role is painted, including accessibility fallbacks. PR 1a ships the `.overlay` role
    /// (system Material — native Reduce-Transparency/Increase-Contrast adaptation, design
    /// §3.2); the fill roles arrive with their consuming PRs.
    func glassPanel(_ role: SurfaceRole, in shape: some InsettableShape) -> some View {
        modifier(GlassPanelModifier(role: role, shape: shape))
    }
}

/// The sanctioned environment→resolver wiring for the glow field (this file is the one
/// place appearance may be read — semgrep rule 4). Renders `content` only when the pure
/// `glowFieldIsVisible` resolver says so (dark + no reduced-transparency request).
struct GlowFieldGate<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        if glowFieldIsVisible(appearance: colorScheme == .dark ? .dark : .light,
                              reduceTransparency: reduceTransparency,
                              increasedContrast: colorSchemeContrast == .increased) {
            content
        }
    }
}

private struct GlassPanelModifier<PanelShape: InsettableShape>: ViewModifier {
    let role: SurfaceRole
    let shape: PanelShape

    // The environment→resolver shim: views never read these flags themselves (semgrep rule 4
    // bans per-view appearance branching; this definition file is the sanctioned reader).
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let resolved = resolveSurface(
            role: role,
            appearance: colorScheme == .dark ? .dark : .light,
            reduceTransparency: reduceTransparency,
            increasedContrast: colorSchemeContrast == .increased
        )
        switch resolved {
        case .systemMaterial(.ultraThin):
            content.background(.ultraThinMaterial, in: shape)
        case .systemMaterial(.bar):
            content.background(.bar, in: shape)
        }
    }
}
