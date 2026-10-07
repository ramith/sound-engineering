// RES-04 + glow-spec invariants (S10.7 PR 2, design §7 R2/§3.3).

import DesignTokenKit
import Testing

@Suite("Glow field — visibility resolver + spec invariants")
struct GlowFieldTests {
    /// The glow field is translucency decoration — any accessibility opacity request wins.
    /// Dark paints it under every light backdrop; light only under the one that glows there
    /// (S10.8 B2b: the pale glow, whose light tokens only brighten — GLOW-01). The others keep
    /// the PR-2 dark-only rule (review MAJOR 4: a mid-luminance hue composited over the
    /// near-white light window DARKENS it — a stain).
    @Test("RES-04: glows render in dark, and in light only under the pale glow; never under RT/IC — full cube")
    func visibilityResolution() {
        for backdrop in LightBackdrop.allCases {
            for appearance in TokenAppearance.allCases {
                for reduceTransparency in [false, true] {
                    for increasedContrast in [false, true] {
                        let visible = glowFieldIsVisible(appearance: appearance,
                                                         reduceTransparency: reduceTransparency,
                                                         increasedContrast: increasedContrast,
                                                         backdrop: backdrop)
                        let painted = appearance == .dark || backdrop == .paleGlow
                        let expected = painted && !reduceTransparency && !increasedContrast
                        #expect(visible == expected,
                                "\(backdrop)/\(appearance)/rt=\(reduceTransparency)/ic=\(increasedContrast)")
                    }
                }
            }
        }
        // Release has no switch: the default is the designed backdrop.
        #expect(glowFieldIsVisible(appearance: .light, reduceTransparency: false, increasedContrast: false)
            == LightBackdrop.designed.glowsInLight)
    }

    /// The light grammar's glow rule (§3.2, re-derived in S10.8 B2b): a light glow is a
    /// luminance-positive pastel — at its peak alpha over the light window, every glow only
    /// BRIGHTENS it, never darkens (the dark hues at ~1/3 alpha did: a grey stain).
    @Test("GLOW-01: every glow's light pastel brightens the light window, never darkens it")
    func lightGlowsBrighten() {
        let window = Palette.window.light
        for glow in GlowFieldSpec.glows {
            let peak = glow.color.light.over(window)
            #expect(peak.relativeLuminance > window.relativeLuminance,
                    "light glow \(glow.color.light) darkens the window: \(peak.relativeLuminance)")
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
