// R4-SLIDER — the carved sliders' and meters' non-text contrast audit (S10.8 B2a). Own file, same
// posture as R4-TAB / R4-CHIP: shares the `ratio` / threshold helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// The carved controls: a white knob on a groove, and the shared teal fill (`meterFill`) whose
/// TRAILING end (`meterFillTrail`) is the value cue — the loudness meters have no knob at all. The
/// sliders and meters sit on the inspector card; the footer scrubber's groove sits on the window.
@Suite("Contrast audit — carved sliders and meters (R4-SLIDER)")
struct SliderAuditTests {
    /// The light surfaces a carved control sits on: the card as it renders (both shadows under its
    /// fill — the worst case), the opaque RT/IC card, and the window (the footer band).
    private static let lightCards = [
        CardSeparationAuditTests.shadedLightFill(Palette.panelFill),
        Palette.panelFill.value(for: .light, increasedContrast: true).over(Palette.window.light),
    ]

    @Test("R4-SLIDER-01: the light knob's ring clears 3:1 on the card and the window")
    func knobRingInLight() {
        for surface in Self.lightCards + [Palette.window.light] {
            let ring = GlassDecor.knobRingLight.over(surface)
            let ratio = RGBAColor.contrastRatio(ring, surface)
            #expect(ratio >= ContrastAuditTests.nonTextAA, "knob ring = \(ratio)")
        }
    }

    @Test("R4-SLIDER-02: the fill's value end clears 3:1 on the card and on the groove, both appearances")
    func fillValueEnd() {
        let surfaces: [(TokenAppearance, [RGBAColor])] = [
            (.light, Self.lightCards),
            (.dark, [Palette.panelFill.dark.over(Palette.window.dark),
                     Palette.panelFill.value(for: .dark, increasedContrast: true).over(Palette.window.dark)]),
        ]
        for (appearance, cards) in surfaces {
            for card in cards {
                let groove = GlassDecor.carvedTrack.value(for: appearance).over(card)
                for (name, backdrop) in [("card", card), ("groove", groove)] {
                    let ratio = ContrastAuditTests.ratio(label: Palette.meterFillTrail, on: backdrop, appearance)
                    #expect(ratio >= ContrastAuditTests.nonTextAA,
                            "meterFillTrail on the \(appearance) \(name) = \(ratio)")
                }
            }
        }
        // The footer scrubber: the value end on the light window band.
        let window = Palette.window.light
        #expect(ContrastAuditTests.ratio(label: Palette.meterFillTrail, on: window, .light)
            >= ContrastAuditTests.nonTextAA, "meterFillTrail on the light window")
    }

    /// The footer groove sits on the bare window, darker than the card: the card's 10% carved a
    /// darker groove there and the value end measured 2.94:1 against it. B3 gives the window its
    /// own groove (`carvedTrackOnWindow`, the card groove's rendered grey) rather than deepening the
    /// one shared fill token again.
    @Test("R4-SLIDER-03: the fill's value end clears 3:1 on the footer groove over the light window")
    func footerGrooveInLight() {
        let groove = GlassDecor.carvedTrackOnWindow.light.over(Palette.window.light)
        let ratio = ContrastAuditTests.ratio(label: Palette.meterFillTrail, on: groove, .light)
        #expect(ratio >= ContrastAuditTests.nonTextAA, "meterFillTrail on the footer groove = \(ratio)")
    }

    /// The founder rule as a test: B2a re-tunes LIGHT only.
    @Test("R4-SLIDER-04: the dark fill, groove and knob are the shipped ones")
    func darkValuesUnchanged() {
        #expect(Palette.meterFillTrail.dark == Palette.iconFillTop.dark)
        #expect(GlassDecor.carvedTrack == AppearancePair(light: .gray(0.0, alpha: 0.10),
                                                         dark: .gray(1.0, alpha: 0.13)))
        #expect(GlassDecor.carvedTrackOnWindow.dark == GlassDecor.carvedTrack.dark)
        #expect(GlassDecor.knobFill.dark == .gray(1.0))
    }
}
