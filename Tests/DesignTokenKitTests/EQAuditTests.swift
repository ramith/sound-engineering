// R4-EQ — the EQ graph's contrast audit (Sprint EQ, EQ3; ui-plan §6). Own file, same posture as
// R4-FOCUS / R4-CHIP: it shares only the thresholds and the glow grid with the base R4 suite.
//
// The graph sits on a lens, on the graph card, over the app glow — and paints washes of its own
// under the curve: the analyzer silhouette, a Tone region's shading, the active band's column and the
// curve's area fill (`EQGraphDecor`). They STACK, so every mark is audited on the lens with none of
// them and with all of them, in both appearances, and on the opaque lens Reduce Transparency and
// Increase Contrast serve.

import DesignTokenKit
import Testing

@Suite("Contrast audit — the EQ graph on its lens (R4-EQ, R4-FOCUS-03, R4-CHIP-EQ)")
struct EQAuditTests {
    /// One composited backdrop a mark can sit on.
    private typealias Backdrop = (name: String, color: RGBAColor)
    /// One appearance column of the audit.
    private typealias Column = (appearance: TokenAppearance, increasedContrast: Bool)

    /// Both appearances, plain and Increase Contrast.
    private static let columns: [Column] =
        TokenAppearance.allCases.flatMap { appearance in [(appearance, false), (appearance, true)] }

    /// Every lens the graph can be drawn on in `column`: its fill over the graph card over the Library
    /// glow at each sampled point, plus the opaque composite Reduce Transparency serves. Increase
    /// Contrast has that opaque lens alone (macOS turns Reduce Transparency on with it, and the glow off).
    private static func lenses(_ column: Column) -> [Backdrop] {
        var lenses: [Backdrop] = []
        if case let .fill(opaque) = resolveSurface(role: .lens, appearance: column.appearance,
                                                   reduceTransparency: true,
                                                   increasedContrast: column.increasedContrast) {
            lenses.append(("opaque lens", opaque))
        }
        guard !column.increasedContrast else { return lenses }
        for (site, glow) in glowSites(column.appearance) {
            let card = Palette.panelFill.value(for: column.appearance).over(glow)
            lenses.append(("lens⊕card⊕glow \(site)", Palette.lensFill.value(for: column.appearance).over(card)))
        }
        return lenses
    }

    /// The app glow under the EQ screen, composited at every sampled point of both reference sizes.
    private static func glowSites(_ appearance: TokenAppearance) -> [Backdrop] {
        ContrastAuditTests.glowGeometries.flatMap { geometry in
            ContrastAuditTests.gridPoints().map { point in
                ("@(\(point.x),\(point.y)) \(geometry.width)pt", GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: appearance, glows: GlowFieldSpec.appGlows
                ))
            }
        }
    }

    /// The washes the graph paints while the EQ plays, bottom to top, with the silhouette at ramp
    /// position `silhouette` (nil: outside the silhouette).
    private static func washes(silhouette: Float?, _ appearance: TokenAppearance) -> [RGBAColor] {
        let analyzer = silhouette.map { [EQGraphDecor.silhouette(at: $0).value(for: appearance)] } ?? []
        return analyzer + [EQGraphDecor.toneShade, EQGraphDecor.activeColumn, EQGraphDecor.curveArea]
            .map { $0.value(for: appearance) }
    }

    /// `lens` under every stack of washes a mark can meet: none, and all of them at each analyzer ramp
    /// stop (and with no silhouette).
    private static func stacks(on lens: Backdrop, _ appearance: TokenAppearance) -> [Backdrop] {
        let positions: [Float?] = [nil] + SpectrumRamp.stops.map(\.position)
        return [lens] + positions.map { position in
            let stacked = washes(silhouette: position, appearance).reduce(lens.color) { $1.over($0) }
            return ("\(lens.name) ⊕ washes (silhouette \(position.map { "\($0)" } ?? "none"))", stacked)
        }
    }

    /// Asserts `mark` (composited onto each backdrop) clears `threshold` on every one.
    private static func expect(_ name: String, _ mark: AppearancePair, on backdrops: [Backdrop],
                               _ threshold: Double, _ column: Column) {
        for backdrop in backdrops {
            let color = mark.value(for: column.appearance, increasedContrast: column.increasedContrast)
                .over(backdrop.color)
            let ratio = RGBAColor.contrastRatio(color, backdrop.color)
            #expect(ratio >= threshold, "\(name) on \(backdrop.name) \(column) = \(ratio)")
        }
    }

    @Test("R4-EQ-01: the curve and beads (accentFill) clear 3:1 on the lens and on every stack of washes")
    func curveAndBeads() {
        for column in Self.columns {
            for lens in Self.lenses(column) {
                Self.expect("accentFill", Palette.accentFill, on: Self.stacks(on: lens, column.appearance),
                            ContrastAuditTests.nonTextAA, column)
            }
        }
    }

    /// The 0 dB line, the band ticks and the neutral rings, and — while nothing plays the curve (Off, a
    /// held Compare, Pure Mode) — the flat curve and the dimmed beads: `labelTertiary` at full strength.
    /// Its text uses (the axis numbers, the region names) sit on the lens outside the plot's washes.
    @Test("R4-EQ-02: labelTertiary clears 3:1 as a mark on every stack, and AA as the axis text on the lens")
    func tertiaryMarksAndAxisText() {
        for column in Self.columns {
            for lens in Self.lenses(column) {
                Self.expect("labelTertiary (mark)", Palette.labelTertiary,
                            on: Self.stacks(on: lens, column.appearance), ContrastAuditTests.nonTextAA, column)
                Self.expect("labelTertiary (axis text)", Palette.labelTertiary, on: [lens],
                            ContrastAuditTests.textAA, column)
            }
        }
    }

    /// The frequency axis sits in the lens's bottom band, where dark carries the light bleed (the lens
    /// keeps it — founder, S10.8 part 2). The numbers' lowest edge is `axisTextDrop` under the plot, so
    /// they meet the bleed at that height, not at its full strength on the lens's last pixel row.
    @Test("R4-EQ-02b: the frequency axis clears AA on the lens's bottom band, where the dark bleed reaches it")
    func axisTextOnBottomBand() {
        let axisTextDrop = 8.0 + 13.0 // the gap under the plot, then the micro mono line
        let heightAboveEdge = EQScreenLayout.plotInsetBottom - axisTextDrop
        let reach = max(0, min(1, (GlassDecor.bleedHeight - heightAboveEdge) / GlassDecor.bleedHeight))
        #expect(reach > 0 && reach < 1, "the axis sits inside the bleed band, above its peak")
        let bleed = GlassDecor.bleedDark.opacity(GlassDecor.bleedDark.alpha * reach)
        let dark: Column = (.dark, false)
        for lens in Self.lenses(dark) {
            Self.expect("labelTertiary (axis text)", Palette.labelTertiary,
                        on: [("\(lens.name) ⊕ bleed", bleed.over(lens.color))], ContrastAuditTests.textAA, dark)
        }
    }

    @Test("R4-EQ-03: the ceiling line (meterHot) clears 3:1 on every stack; its text (meterHotText) AA on the lens")
    func ceiling() {
        for column in Self.columns {
            for lens in Self.lenses(column) {
                Self.expect("meterHot", Palette.meterHot, on: Self.stacks(on: lens, column.appearance),
                            ContrastAuditTests.nonTextAA, column)
                Self.expect("meterHotText", Palette.meterHotText, on: [lens], ContrastAuditTests.textAA, column)
            }
        }
    }

    /// The drag readout is `label` on its own opaque capsule (the panel fill over the window, painted
    /// over the lens). The active point's edge is what sets it off the curve under it: its white rim in
    /// dark, the knob's dark ring in light (`EQPointHandle`).
    @Test("R4-EQ-04: the drag tag's text clears AA; the active point's edge clears 3:1 on every stack")
    func tagAndHandle() {
        for column in Self.columns {
            let window = Palette.window.value(for: column.appearance, increasedContrast: column.increasedContrast)
            let tag = Palette.panelFill.value(for: column.appearance, increasedContrast: column.increasedContrast)
                .over(window)
            Self.expect("label (drag tag)", Palette.label, on: [("panelFill⊕window", tag)],
                        ContrastAuditTests.textAA, column)
            let edge = column.appearance == .dark
                ? AppearancePair(both: GlassDecor.knobFill.dark)
                : AppearancePair(both: GlassDecor.knobRingLight)
            for lens in Self.lenses(column) {
                Self.expect("the handle's edge", edge, on: Self.stacks(on: lens, column.appearance),
                            ContrastAuditTests.nonTextAA, column)
            }
        }
    }

    @Test("R4-FOCUS-03: focusRing clears 3:1 around the keyboard cursor's point, on every stack")
    func focusRingOnLens() {
        for column in Self.columns {
            for lens in Self.lenses(column) {
                Self.expect("focusRing", Palette.focusRing, on: Self.stacks(on: lens, column.appearance),
                            ContrastAuditTests.nonTextAA, column)
            }
        }
    }

    /// The chips beside the preset's name, on the graph card over the glow: "Edited" is `accentText` on
    /// the chip's on fill; "Off" is `labelSecondary` on the badge wash.
    @Test("R4-CHIP-EQ: the Edited and Off chips' text clears AA on the graph card over the glow")
    func stateChips() {
        for appearance in TokenAppearance.allCases {
            let column: Column = (appearance, false)
            for (site, glow) in Self.glowSites(appearance) {
                let card = Palette.panelFill.value(for: appearance).over(glow)
                let edited = Palette.controlActiveFill.value(for: appearance).over(card)
                let off = Palette.badgeFill.value(for: appearance).over(card)
                Self.expect("accentText (Edited)", Palette.accentText,
                            on: [("controlActiveFill⊕card⊕glow \(site)", edited)], ContrastAuditTests.textAA, column)
                Self.expect("labelSecondary (Off)", Palette.labelSecondary,
                            on: [("badgeFill⊕card⊕glow \(site)", off)], ContrastAuditTests.textAA, column)
            }
        }
    }
}
