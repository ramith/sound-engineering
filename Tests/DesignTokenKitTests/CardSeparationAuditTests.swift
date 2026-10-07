// CARD-SEP — the light glass card's separation from the window (S10.8 B2a). Own file, same
// posture as R4-TAB / R4-CHIP: shares the `ratio` / threshold helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// The light card must read as a card: in dark the floating cards render 1.10–1.17:1 against the
/// window (measured on the picture sheets); the shipped 60% light card rendered 1.06:1. Audited on
/// what RENDERS, not the token math: the shadows a fill shape casts show THROUGH its translucent
/// fill, so the 60% card was #F3F3F3 on screen, not the #F8F8F8 its tokens compose to.
@Suite("Card separation — light glass card (CARD-SEP)")
struct CardSeparationAuditTests {
    /// The floor. Not a WCAG pair (the card's content carries the meaning, and the rim and
    /// hairline draw its edge); a regression net for "the card disappears into the window".
    static let minimumSeparation = 1.08

    /// The worst case of a light glass fill as it renders: both light shadows (key + contact)
    /// at full alpha under the translucent fill — a rendered pixel is never darker than this.
    static func shadedLightFill(_ fill: AppearancePair) -> RGBAColor {
        let window = Palette.window.light
        let shaded = GlassDecor.contactShadowLight.over(GlassDecor.shadowColor.light.over(window))
        return fill.light.over(shaded)
    }

    @Test("CARD-SEP-01: the light card separates from the window even with both shadows under its fill")
    func lightCardSeparation() {
        let window = Palette.window.light
        let card = Self.shadedLightFill(Palette.panelFill)
        let ratio = RGBAColor.contrastRatio(card, window)
        #expect(ratio >= Self.minimumSeparation, "light card ⊕ shadows vs window = \(ratio)")
        // Reduce Transparency / Increase Contrast: the resolver's opaque card hides the shadows.
        let opaque = Palette.panelFill.value(for: .light, increasedContrast: true).over(window)
        #expect(RGBAColor.contrastRatio(opaque, window) >= Self.minimumSeparation,
                "opaque light card vs window")
    }

    /// The founder rule as a test: B2a re-tunes LIGHT only — the dark card recipe stays as shipped.
    @Test("CARD-SEP-02: the dark card recipe is unchanged")
    func darkRecipeUnchanged() {
        #expect(GlassDecor.shadowColor.dark == .gray(0.0, alpha: 0.60))
        #expect(GlassDecor.shadowRadiusDark == 36)
        #expect(GlassDecor.shadowOffsetYDark == 14)
        #expect(Palette.panelFill.dark == RGBAColor(red: 30.0 / 255.0, green: 32.0 / 255.0,
                                                    blue: 37.0 / 255.0, alpha: 0.72))
        #expect(Palette.lensFill.dark == RGBAColor(red: 16.0 / 255.0, green: 18.0 / 255.0,
                                                   blue: 21.0 / 255.0, alpha: 0.42))
    }
}
