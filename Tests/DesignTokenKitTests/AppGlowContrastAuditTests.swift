// R4 contrast audit for the app glow (S10.8 F1, decision 2; born as the Library Twin Panels
// backdrop audit, S10.8 Library PR-B). Every tab but Now Playing — Library, EQ, Monitoring and
// Settings — sits on ONE single teal pool (`GlowFieldSpec.appGlows`), mounted once by the shell,
// instead of Now Playing's three-glow field. This suite folds that glow through the SAME
// `compositeBackdrop` math the render reads, so the "the audit reads the render data" invariant
// holds for every tab's backdrop, and any founder center/size tuning re-verifies automatically.
// The light side of the same field is audited by LightGlowAuditTests; Monitoring's own colours
// over it by MonitorAuditTests.
//
// A SEPARATE suite (not added to `ContrastAuditTests`) because that struct is already at the
// type-body-length limit; it reuses that suite's internal grid/ratio helpers so both audit the
// same geometry and WCAG math.

import DesignTokenKit
import Testing

@Suite("Contrast audit — the app glow behind every tab but Now Playing (R4)")
struct AppGlowContrastAuditTests {
    /// label + labelSecondary clear AA at every sampled point of the app glow (dark): the text a tab
    /// sets straight on its backdrop (Monitoring's header and legend, the empty states).
    /// Safe by DOMINATION — the app glow's peak backdrop is window⊕glowTeal, the SAME worst case
    /// `R4-GLOW-01` already clears over Now Playing's STRONGER three-glow field — but audited
    /// directly against `appGlows` so it re-verifies on any later glow center/size tuning.
    ///
    /// `labelTertiary` is intentionally NOT audited on the bare glow: tertiary/caption text is
    /// card-bound (it renders on `.glassPanel(.panel)` surfaces, never on the bare glow),
    /// mirroring NP's rule that keeps tertiary text out of the teal core. R4-GLOW-APP-02 audits
    /// it on the card.
    @Test("R4-GLOW-APP-01: label + labelSecondary clear AA across the app glow (dark)")
    func primaryLabelsOnAppGlow() {
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                let backdrop = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark,
                    glows: GlowFieldSpec.appGlows
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

    /// The glass cards over the app glow — the Library's ONE detail card (S10.8 D1, every category,
    /// page and playlist), the EQ's rail and graph cards — can sit anywhere over the glow, its peak
    /// included, so their tertiary text (count lines, captions, headers) can too. The label hierarchy
    /// clears AA on the card's fill over the app glow at every sampled point, in both appearances (the
    /// light glow is the pale one).
    @Test("R4-GLOW-APP-02: labelTertiary (and the hierarchy) clears AA on the card over the app glow")
    func labelsOnCardOverGlow() {
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
                        glows: GlowFieldSpec.appGlows
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

    /// The Library rail's idle nav label (`labelNav`, ~72%) clears AA on the panel card fill it sits
    /// on, both appearances (the RT/IC opaque composite too). A touch stronger than `labelSecondary`
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
