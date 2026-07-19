// TOK — palette-wide invariants (design §7 R2), driven by the `Palette.all` registry so a
// token missing from the registry is itself a reviewable gap, not a silent one. (TOK-01, the
// radii-concentricity chain, joins when `Glass.Radius` lands with the fill roles.)

import DesignTokenKit
import Testing

@Suite("Palette invariants (TOK)")
struct TokenInvariantTests {
    /// Channels and alpha in [0, 1]; a fully-transparent token is a mistake, not a color.
    @Test("TOK-02: every registered token has valid channel + alpha values")
    func componentRanges() {
        for (name, pair) in Palette.all {
            for appearance in TokenAppearance.allCases {
                for increasedContrast in [false, true] {
                    let value = pair.value(for: appearance, increasedContrast: increasedContrast)
                    for (channel, label) in [(value.red, "red"), (value.green, "green"),
                                             (value.blue, "blue"), (value.alpha, "alpha")] {
                        #expect((0.0 ... 1.0).contains(channel),
                                "\(name).\(appearance) \(label) out of range: \(channel)")
                    }
                    #expect(value.alpha > 0, "\(name).\(appearance) is fully transparent")
                }
            }
        }
    }

    /// So Increase Contrast can never resolve to an unset/garbage value.
    @Test("TOK-03: high-contrast variants default to base values until a token opts in")
    func highContrastDefaults() {
        // Deliberate opt-ins (each names its design contract; anything NOT listed must
        // still default — a new distinct HC variant fails here until added deliberately):
        //   glassHairline — §3.2 "stronger hairlines under Increase Contrast" (PR 3).
        let optedIn: Set = ["glassHairline"]
        for (name, pair) in Palette.all {
            for appearance in TokenAppearance.allCases {
                let base = pair.value(for: appearance, increasedContrast: false)
                let highContrast = pair.value(for: appearance, increasedContrast: true)
                if optedIn.contains(name) {
                    #expect(highContrast.alpha > base.alpha,
                            "\(name).\(appearance): an opted-in hairline must be STRONGER under IC")
                } else {
                    #expect(highContrast == base,
                            "\(name).\(appearance): unexpected distinct HC variant — update this test if intentional")
                }
            }
        }
    }

    /// rowNowPlaying/rowSelected/controlActiveFill are the accent at documented alphas,
    /// never drifting values.
    @Test("TOK-04: derived accent tints stay derived from the accent")
    func rowTintsDeriveFromAccent() {
        let accent = Palette.accent.light
        #expect(Palette.rowNowPlaying.light == accent.opacity(0.13))
        #expect(Palette.rowSelected.light == accent.opacity(0.12))
        #expect(Palette.controlActiveFill.light == accent.opacity(0.16))
        for (name, pair) in [("rowNowPlaying", Palette.rowNowPlaying),
                             ("rowSelected", Palette.rowSelected),
                             ("controlActiveFill", Palette.controlActiveFill)] {
            #expect(pair.light == pair.dark,
                    "\(name) is appearance-independent (accent-derived)")
        }
    }

    /// The 8a concentric chain (§3.2): outer radii are never smaller than inner ones.
    /// Grows as roles land (rows/badges join with their tokens).
    @Test("TOK-01: the glass radii chain stays monotone (panel ≥ lens)")
    func radiiChain() {
        #expect(GlassDecor.panelRadius >= GlassDecor.lensRadius,
                "panel \(GlassDecor.panelRadius) must be ≥ lens \(GlassDecor.lensRadius)")
    }

    /// The audit engine's ground truth: opaque-over-anything is itself; results go opaque.
    @Test("TOK-05: compositing sanity — opaque identity + opaque results")
    func compositingGroundTruth() {
        let backdrop = Palette.window.dark
        let opaque = Palette.accent.light
        #expect(opaque.over(backdrop) == opaque)
        let translucent = Palette.card.dark
        let composite = translucent.over(backdrop)
        #expect(composite.alpha == 1.0, "translucent over opaque must yield opaque")
    }
}
