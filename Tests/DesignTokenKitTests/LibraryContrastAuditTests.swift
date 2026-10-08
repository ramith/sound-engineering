// R4 contrast audit for the Library Twin Panels backdrop (S10.8 Library PR-B). The Library
// screen renders a SINGLE teal ambient glow (`GlowFieldSpec.libraryGlows`) instead of Now
// Playing's three-glow field. This suite folds that glow through the SAME `compositeBackdrop`
// math the render reads, restoring the "the audit reads the render data" invariant for the
// new backdrop — so any founder center/size tuning in the later Twin Panels PRs re-verifies
// automatically.
//
// A SEPARATE suite (not added to `ContrastAuditTests`) because that struct is already at the
// type-body-length limit; it reuses that suite's internal grid/ratio helpers so both audit the
// same geometry and WCAG math.

import DesignTokenKit
import Testing

@Suite("Contrast audit — Library Twin Panels glow (R4)")
struct LibraryContrastAuditTests {
    /// label + labelSecondary clear AA at every sampled point of the Library glow (dark).
    /// Safe by DOMINATION — the Library peak backdrop is window⊕glowTeal, the SAME worst case
    /// `R4-GLOW-01` already clears over Now Playing's STRONGER three-glow field — but audited
    /// directly against `libraryGlows` so it re-verifies on any later glow center/size tuning.
    ///
    /// `labelTertiary` is intentionally NOT audited on the bare glow: Library tertiary/caption
    /// text is card-bound (it renders on `.glassPanel(.panel)` surfaces, never on the bare
    /// glow), mirroring NP's rule that keeps tertiary text out of the teal core. Tertiary over
    /// the card⊕glow composite is a later Twin Panels PR's audit, once the cards land.
    @Test("R4-GLOW-LIB-01: label + labelSecondary clear AA across the Library glow (dark)")
    func primaryLabelsOnLibraryGlow() {
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                let backdrop = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark,
                    glows: GlowFieldSpec.libraryGlows
                )
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = ContrastAuditTests.ratio(label: label, on: backdrop, .dark)
                    #expect(ratio >= ContrastAuditTests.textAA,
                            "\(name) @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
                }
            }
        }
    }

    /// The Library's ONE detail card (S10.8 D1) now holds every category, page and playlist, so its
    /// tertiary text — the count lines, the grids' captions, the playlist header — can sit anywhere
    /// over the glow, its peak included. The label hierarchy clears AA on the card's fill over the
    /// Library glow at every sampled point, in both appearances (the light glow is the pale one).
    @Test("R4-GLOW-LIB-02: labelTertiary (and the hierarchy) clears AA on the card over the Library glow")
    func labelsOnDetailCardOverGlow() {
        let labels: [(String, AppearancePair)] = [
            ("label", Palette.label), ("labelSecondary", Palette.labelSecondary),
            ("labelTertiary", Palette.labelTertiary),
        ]
        for appearance in TokenAppearance.allCases {
            for geometry in ContrastAuditTests.glowGeometries {
                for point in ContrastAuditTests.gridPoints() {
                    let glow = GlowFieldSpec.compositeBackdrop(
                        unitX: point.x, unitY: point.y,
                        containerWidth: geometry.width, containerHeight: geometry.height,
                        appearance: appearance,
                        glows: GlowFieldSpec.libraryGlows
                    )
                    let card = Palette.panelFill.value(for: appearance).over(glow)
                    for (name, label) in labels {
                        let ratio = ContrastAuditTests.ratio(label: label, on: card, appearance)
                        #expect(ratio >= ContrastAuditTests.textAA,
                                "\(name) on card⊕glow (\(appearance)) @(\(point.x),\(point.y)) = \(ratio)")
                    }
                }
            }
        }
    }

    /// The rail's idle nav label (`labelNav`, ~72%) clears AA on the panel card fill it sits on,
    /// both appearances (the RT/IC opaque composite too). A touch stronger than `labelSecondary`
    /// (already AA on the panel), so it clears by domination — audited directly since it's a new
    /// tier the base R4-LEG suite doesn't enumerate.
    @Test("R4-LEG-LIB-01: labelNav clears AA on the rail panel card, both appearances")
    func navLabelOnPanelCard() {
        for appearance in TokenAppearance.allCases {
            let surface = Palette.panelFill.value(for: appearance)
                .over(Palette.window.value(for: appearance))
            let ratio = ContrastAuditTests.ratio(label: Palette.labelNav, on: surface, appearance)
            #expect(ratio >= ContrastAuditTests.textAA,
                    "labelNav on panelFill over window (\(appearance)) = \(ratio)")
        }
    }
}
