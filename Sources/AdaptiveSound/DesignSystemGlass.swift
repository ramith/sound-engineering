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

extension View {
    /// The hero-title style (S10.7 PR 4): `heroTitle` font, primary label color, and the 8a
    /// teal halo — DARK-ONLY (grammar rule 6: light drops emissive cues). Lives here because
    /// this file is the sanctioned appearance reader.
    func heroTitle() -> some View {
        modifier(HeroTitleModifier())
    }
}

private struct HeroTitleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Font.heroTitle)
            .foregroundStyle(DesignSystem.Color.label)
            .shadow(color: colorScheme == .dark ? SwiftUI.Color(token: GlassDecor.heroHaloDark) : .clear,
                    radius: CGFloat(GlassDecor.heroHaloRadius),
                    x: 0,
                    y: CGFloat(GlassDecor.heroHaloOffsetY))
    }
}

// MARK: - Carved slider visuals (S10.7 PR 5 — the 8a track/knob recipe)

/// The 8a carved GROOVE (track): a token-filled base with a top inner shade (the inset
/// shadow) and a teal progress fill with a dark-only glow (grammar rule 6). Appearance-aware,
/// so it lives in this sanctioned file. Shared by the inspector `CarvedSlider` AND the footer
/// scrubber (PR 6) — one carved surface, two consumers. Vertically centered in whatever height
/// the caller frames it to; the knob/thumb is the caller's concern.
struct CarvedGroove: View {
    /// The teal-filled portion, as a fraction [0, 1] of the track width.
    let fillFraction: Double
    /// Track (groove) thickness.
    var height: CGFloat = .init(GlassDecor.carvedTrackHeight)
    /// The progress fill (S10.8 PR E: the realigned mid→bright teal gradient by default —
    /// sliders, meters, and the playing scrubber share it; the scrubber's paused/
    /// interrupted states pass their solid state colors instead).
    var fillStyle: AnyShapeStyle = .init(DesignSystem.Gradient.meterFill)
    /// Whether the fill carries the dark-only teal glow (off when the fill isn't the accent
    /// family — e.g. the scrubber paused/interrupted — so a teal glow never sits under a
    /// grey fill).
    var glow: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private static let innerShade: CGFloat = 2

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { geo in
            let clamped = CGFloat(min(max(fillFraction, 0), 1))
            ZStack(alignment: .leading) {
                // Carved base: token fill + a top inner shade (the 8a inset shadow).
                Capsule()
                    .fill(SwiftUI.Color(token: GlassDecor.carvedTrack.value(for: dark ? .dark : .light)))
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [SwiftUI.Color(token: dark ? GlassDecor.carvedShadeDark
                                    : GlassDecor.carvedShadeLight), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: Self.innerShade)
                    }
                    .clipShape(Capsule())
                    .frame(height: height)

                Capsule()
                    .fill(fillStyle)
                    .frame(width: geo.size.width * clamped, height: height)
                    .shadow(color: (dark && glow) ? SwiftUI.Color(token: GlassDecor.sliderGlowDark) : .clear,
                            radius: 5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// The 8a carved knob/thumb: a token-filled circle with a bottom inner shade (the physical
/// cue, both appearances). Shared by the slider knob and the footer scrubber's hover thumb.
struct CarvedKnob: View {
    var size: CGFloat = .init(GlassDecor.sliderKnobSize)

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Circle()
            .fill(SwiftUI.Color(token: GlassDecor.knobFill.value(for: dark ? .dark : .light)))
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, SwiftUI.Color(token: GlassDecor.knobShade)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(Circle())
            }
            .frame(width: size, height: size)
    }
}

/// The inspector slider's track+knob (S10.7 PR 5). Composes the shared `CarvedGroove` (fill to
/// the knob CENTER, so the teal meets the knob at every position) + a `CarvedKnob` at the
/// knob's inset travel position. `CarvedSlider` (UI/Controls) owns interaction.
struct CarvedTrack: View {
    /// Filled fraction in [0, 1].
    let fraction: Double

    private static let knobSize = CGFloat(GlassDecor.sliderKnobSize)

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - Self.knobSize, 0)
            let knobX = usable * CGFloat(min(max(fraction, 0), 1))
            // The teal reaches the knob's CENTER at every position (identical to the PR-5
            // fill width `knobX + knobSize/2`, expressed as a fraction of the track width).
            let fillFraction = Double((knobX + Self.knobSize / 2) / max(geo.size.width, 1))
            ZStack(alignment: .leading) {
                CarvedGroove(fillFraction: fillFraction)
                CarvedKnob()
                    .offset(x: knobX)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: Self.knobSize)
    }
}

// MARK: - Inspector card glow (S10.8 PR E — realigned `png/05`)

/// The teal radial glow behind/below the floating inspector card: rendered only when the
/// glow field itself is visible (dark + no Reduce Transparency — `GlowFieldGate`), and
/// extending past the card's bottom so the empty area under the hugged card reads
/// intentional. Appearance-gated, so it lives in this sanctioned file.
struct InspectorCardGlow: View {
    var body: some View {
        GlowFieldGate {
            RadialGradient(
                colors: [SwiftUI.Color(token: GlassDecor.inspectorGlowDark), .clear],
                center: .center,
                startRadius: 0,
                endRadius: CGFloat(GlassDecor.inspectorGlowRadius)
            )
            .padding(.bottom, -CGFloat(GlassDecor.inspectorGlowBleed))
            .blur(radius: CGFloat(GlassDecor.inspectorGlowBlur))
        }
    }
}

// MARK: - Capsule tab strip visuals (S10.8 PR B — the realigned 8a tab selector)

/// The tab strip's carved track: the `tabTrack` token fill + the shared carved top inner
/// shade (the same inset-shadow cue as `CarvedGroove` — one carved grammar, two consumers).
/// Appearance-aware, so it lives in this sanctioned file.
struct TabTrackCapsule: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Capsule()
            .fill(SwiftUI.Color(token: Palette.tabTrack.value(for: dark ? .dark : .light)))
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [SwiftUI.Color(token: dark ? GlassDecor.carvedShadeDark
                            : GlassDecor.carvedShadeLight), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 2)
            }
            .clipShape(Capsule())
    }
}

/// A teal "glossy button" fill for any insettable shape: the brand `iconFill` gradient
/// (the realigned "teal button" IS this gradient — byte-identical stops), the shared
/// specular top rim, and a dark-only teal glow (grammar rule 6: light drops emissive
/// cues). Consumers: the active tab capsule (PR B) and the footer play circle (PR G).
struct TealGloss<GlossShape: InsettableShape>: View {
    var shape: GlossShape

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let appearance: TokenAppearance = colorScheme == .dark ? .dark : .light
        shape
            .fill(DesignSystem.Gradient.iconFill)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [SwiftUI.Color(token: GlassDecor.rim.value(for: appearance)), .clear],
                        startPoint: .top, endPoint: .center
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: appearance == .dark ? SwiftUI.Color(token: GlassDecor.tabActiveGlowDark) : .clear,
                    radius: CGFloat(GlassDecor.tabActiveGlowRadius),
                    x: 0,
                    y: CGFloat(GlassDecor.tabActiveGlowOffsetY))
    }
}

/// The active tab's teal capsule (S10.8 PR B) — the capsule instance of `TealGloss`.
struct ActiveTabCapsule: View {
    var body: some View {
        TealGloss(shape: Capsule())
    }
}

// MARK: - Chrome band styled glass (S10.8 PR G — realigned `png/01` + `png/06`)

/// The app-owned chrome bands' "styled glass" (founder decision 2: fill strata, NOT real
/// blur — nothing scrolls behind these bands). Dark: the window base + a sheen gradient
/// lit from `lightFrom`, a 1px specular line on the band's TOP edge, and (header only) a
/// dark seam on its bottom edge. Light: the plain window + hairline seams — the grammar
/// drops emissive cues. Owns what AppShell's `.background` + `Hairline` overlays did.
struct ChromeBandModifier: ViewModifier {
    /// `.top` for the header (lit from its top edge), `.bottom` for the footer.
    var lightFrom: UnitPoint = .top

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        content
            .background {
                ZStack {
                    DesignSystem.Color.window
                    if dark {
                        LinearGradient(
                            colors: [SwiftUI.Color(token: GlassDecor.bandSheenStrong),
                                     SwiftUI.Color(token: GlassDecor.bandSheenWeak)],
                            startPoint: lightFrom,
                            endPoint: lightFrom == .top ? .bottom : .top
                        )
                    }
                }
            }
            // The specular line ALWAYS sits on the band's top edge (the edge that catches
            // light — the realign guide's StyledGlassBar contract). Light keeps only the
            // SEPARATING hairlines the bands had before (footer top; header top is the
            // window edge — nothing to separate).
            .overlay(alignment: .top) {
                if dark || lightFrom == .bottom {
                    Rectangle()
                        .fill(dark ? SwiftUI.Color(token: GlassDecor.bandSpecularDark)
                            : DesignSystem.Color.hairline)
                        .frame(height: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if lightFrom == .top { // header: dark seam against the content below
                    Rectangle()
                        .fill(dark ? SwiftUI.Color(token: GlassDecor.bandSeamDark)
                            : DesignSystem.Color.hairline)
                        .frame(height: 1)
                }
            }
    }
}

extension View {
    /// Apply the realigned chrome-band treatment (see `ChromeBandModifier`).
    func chromeBand(lightFrom: UnitPoint) -> some View {
        modifier(ChromeBandModifier(lightFrom: lightFrom))
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
        let appearance: TokenAppearance = colorScheme == .dark ? .dark : .light
        let resolved = resolveSurface(
            role: role,
            appearance: appearance,
            reduceTransparency: reduceTransparency,
            increasedContrast: colorSchemeContrast == .increased
        )
        switch resolved {
        case .systemMaterial(.ultraThin):
            content.background(.ultraThinMaterial, in: shape)
        case .systemMaterial(.bar):
            content.background(.bar, in: shape)
        case let .fill(fill):
            decorated(content, fill: fill, appearance: appearance)
        }
    }

    /// The Regime-B strata (design §3.2): fill (+ dark-only bottom bleed) UNDER the content;
    /// top-edge specular rim + full glass hairline as distinct strokes above; a soft deep
    /// drop shadow (light = ~half opacity, tighter — grammar rule 4). The hairline token
    /// carries real Increase-Contrast variants (the "stronger hairlines under IC" promise);
    /// the resolver already handed us an OPAQUE fill under RT/IC.
    private func decorated(_ content: Content, fill: RGBAColor,
                           appearance: TokenAppearance) -> some View {
        let increasedContrast = colorSchemeContrast == .increased
        let rim = SwiftUI.Color(token: GlassDecor.rim.value(for: appearance))
        let hairline = SwiftUI.Color(token: GlassDecor.glassHairline.value(
            for: appearance, increasedContrast: increasedContrast
        ))
        let shadow = SwiftUI.Color(token: GlassDecor.shadowColor.value(for: appearance))
        let dark = appearance == .dark
        return content
            .background {
                ZStack(alignment: .bottom) {
                    shape.fill(SwiftUI.Color(token: fill))
                    if dark { // bottom light bleed is dark-only (grammar rule 3)
                        LinearGradient(colors: [.clear, SwiftUI.Color(token: GlassDecor.bleedDark)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: CGFloat(GlassDecor.bleedHeight))
                            .clipShape(shape)
                    }
                }
            }
            .overlay { // specular top rim: a top-weighted stroke, never a full-perimeter ring
                shape.strokeBorder(
                    LinearGradient(colors: [rim, .clear], startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
            }
            .overlay { shape.strokeBorder(hairline, lineWidth: 1) }
            .shadow(color: shadow,
                    radius: CGFloat(dark ? GlassDecor.shadowRadiusDark : GlassDecor.shadowRadiusLight),
                    x: 0,
                    y: CGFloat(dark ? GlassDecor.shadowOffsetYDark : GlassDecor.shadowOffsetYLight))
    }
}
