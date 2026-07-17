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
        for (name, pair) in Palette.all {
            for appearance in TokenAppearance.allCases {
                let base = pair.value(for: appearance, increasedContrast: false)
                let highContrast = pair.value(for: appearance, increasedContrast: true)
                // Today NO token opts into a distinct HC variant (they arrive with the
                // fill roles); equality asserts the defaulting path, the only wiring that
                // exists yet. When a token opts in, remove it from this loop — this test
                // failing IS the reminder to do so deliberately.
                #expect(highContrast == base,
                        "\(name).\(appearance): unexpected distinct HC variant — update this test if intentional")
            }
        }
    }

    /// rowNowPlaying/rowSelected are the accent at documented alphas, never drifting values.
    @Test("TOK-04: derived row tints stay derived from the accent")
    func rowTintsDeriveFromAccent() {
        let accent = Palette.accent.light
        #expect(Palette.rowNowPlaying.light == accent.opacity(0.25))
        #expect(Palette.rowSelected.light == accent.opacity(0.12))
        #expect(Palette.rowNowPlaying.light == Palette.rowNowPlaying.dark,
                "row tints are appearance-independent (accent-derived)")
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
