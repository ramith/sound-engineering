// RES-04 + glow-spec invariants (S10.7 PR 2, design §7 R2/§3.3).

import DesignTokenKit
import Testing

@Suite("Glow field — visibility resolver + spec invariants")
struct GlowFieldTests {
    /// The glow field is translucency decoration: any accessibility opacity request wins.
    @Test("RES-04: glows suppressed under Reduce Transparency AND under Increase Contrast alone")
    func visibilityResolution() {
        #expect(glowFieldIsVisible(reduceTransparency: false, increasedContrast: false))
        #expect(!glowFieldIsVisible(reduceTransparency: true, increasedContrast: false))
        // IC alone must suppress even though macOS usually couples IC→RT (RES-02 doctrine:
        // never depend on the OS doing the coupling).
        #expect(!glowFieldIsVisible(reduceTransparency: false, increasedContrast: true))
        #expect(!glowFieldIsVisible(reduceTransparency: true, increasedContrast: true))
    }

    /// Light-grammar rule 5 (§3.2): light glows are AMBIENCE — materially subtler than dark.
    @Test("GLOW-01: every glow's light alpha is at most half its dark alpha (grammar rule 5)")
    func lightAlphasAreSubtler() {
        for glow in GlowFieldSpec.glows {
            #expect(glow.color.light.alpha <= glow.color.dark.alpha / 2,
                    "light glow alpha \(glow.color.light.alpha) vs dark \(glow.color.dark.alpha)")
        }
    }

    /// The falloff constants stay a falloff (mid inside the radius, factor a genuine fade).
    @Test("GLOW-02: falloff stops are well-formed (0 < mid < 1; 0 < factor < 1)")
    func falloffWellFormed() {
        #expect(GlowFieldSpec.falloffMidStop > 0 && GlowFieldSpec.falloffMidStop < 1)
        #expect(GlowFieldSpec.falloffMidAlphaFactor > 0 && GlowFieldSpec.falloffMidAlphaFactor < 1)
    }
}
