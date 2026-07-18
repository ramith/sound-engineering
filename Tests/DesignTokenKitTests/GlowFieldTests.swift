// RES-04 + glow-spec invariants (S10.7 PR 2, design §7 R2/§3.3).

import DesignTokenKit
import Testing

@Suite("Glow field — visibility resolver + spec invariants")
struct GlowFieldTests {
    /// The glow field is dark-only translucency decoration (PR-2 review MAJOR 4: any
    /// mid-luminance hue composited over the near-white light window DARKENS it — a stain);
    /// any accessibility opacity request also wins.
    @Test("RES-04: glows render only in dark with no RT/IC request — full cube")
    func visibilityResolution() {
        for appearance in TokenAppearance.allCases {
            for reduceTransparency in [false, true] {
                for increasedContrast in [false, true] {
                    let visible = glowFieldIsVisible(appearance: appearance,
                                                     reduceTransparency: reduceTransparency,
                                                     increasedContrast: increasedContrast)
                    let expected = appearance == .dark && !reduceTransparency && !increasedContrast
                    #expect(visible == expected,
                            "\(appearance)/rt=\(reduceTransparency)/ic=\(increasedContrast)")
                }
            }
        }
    }

    /// Light-grammar rule 5 (§3.2): the light alphas stay recorded as the S10.8 starting
    /// point (materially subtler than dark) even though the resolver suppresses light
    /// rendering entirely this sprint.
    @Test("GLOW-01: every glow's light alpha is at most half its dark alpha (grammar rule 5)")
    func lightAlphasAreSubtler() {
        for glow in GlowFieldSpec.glows {
            #expect(glow.color.light.alpha <= glow.color.dark.alpha / 2,
                    "light glow alpha \(glow.color.light.alpha) vs dark \(glow.color.dark.alpha)")
        }
    }

    /// The falloff profile is the mock's exact-linear ramp (PR-2 review MAJOR 3): endpoints
    /// pinned, mid stop on the line, monotone decreasing — derived from the constants, so a
    /// stop retune keeps the profile honest or fails loud.
    @Test("GLOW-02: falloffFraction is the exact-linear ramp through the declared stops")
    func falloffProfile() {
        #expect(GlowFieldSpec.falloffFraction(at: 0) == 1)
        #expect(GlowFieldSpec.falloffFraction(at: 1) == 0)
        #expect(abs(GlowFieldSpec.falloffFraction(at: GlowFieldSpec.falloffMidStop)
                - GlowFieldSpec.falloffMidAlphaFactor) < 1e-12)
        // Exact linearity of both segments (slope −1 when factor = 1 − midStop·slope):
        let quarter = GlowFieldSpec.falloffMidStop / 2
        let expectedAtQuarter = 1 - (1 - GlowFieldSpec.falloffMidAlphaFactor) / 2
        #expect(abs(GlowFieldSpec.falloffFraction(at: quarter) - expectedAtQuarter) < 1e-12)
        var previous = 1.0
        for step in 1 ... 20 {
            let value = GlowFieldSpec.falloffFraction(at: Double(step) / 20)
            #expect(value <= previous, "falloff must be monotone decreasing")
            previous = value
        }
    }

    /// The seam feather exists while the shell bands are flat (removed in PR 6).
    @Test("GLOW-03: seam feather is a real run of points")
    func seamFeather() {
        #expect(GlowFieldSpec.seamFeather > 0)
    }
}
