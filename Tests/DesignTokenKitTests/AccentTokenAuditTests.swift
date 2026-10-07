// R4-TINT — the accent ROLE tokens' contrast audit (S10.8 A2). Its own file: the base
// ContrastAuditTests suite is at the SwiftLint length limit; this shares only its
// `ratio`/threshold helpers (same posture as R4-TAB / R4-CHIP).

import DesignTokenKit
import Testing

/// `accentFill` (tints, switch tracks, glyph fill layers — non-text 3:1) and
/// `accentForeground` (teal text and glyphs — text AA 4.5:1) audited on every surface they
/// sit on, in both appearances, plus the `onAccent` glyph drawn on an `accentFill` disc. The
/// founder rule — no shipped DARK look changes — is a test too: both roles' dark value IS the
/// bare accent's.
@Suite("Contrast audit — accent roles (R4-TINT)")
struct AccentTokenAuditTests {
    /// The plain window plus a translucent fill composited over it, per appearance.
    private static func surfaces(
        over fills: [(name: String, pair: AppearancePair)],
        _ appearance: TokenAppearance
    ) -> [(name: String, color: RGBAColor)] {
        let window = Palette.window.value(for: appearance)
        return [("window", window)] + fills.map { fill in
            ("\(fill.name)⊕window", fill.pair.value(for: appearance).over(window))
        }
    }

    @Test("R4-TINT-01: accentFill clears non-text 3:1 on the window and the panel, both appearances")
    func fillContrast() {
        for appearance in TokenAppearance.allCases {
            for surface in Self.surfaces(over: [("panelFill", Palette.panelFill)], appearance) {
                let ratio = ContrastAuditTests.ratio(label: Palette.accentFill, on: surface.color, appearance)
                #expect(ratio >= ContrastAuditTests.nonTextAA,
                        "accentFill on \(surface.name) (\(appearance)) = \(ratio)")
            }
        }
    }

    @Test("R4-TINT-02: accentForeground clears text AA on window, panel and badge, both appearances")
    func foregroundContrast() {
        let fills = [("panelFill", Palette.panelFill), ("badgeFill", Palette.badgeFill)]
        for appearance in TokenAppearance.allCases {
            for surface in Self.surfaces(over: fills, appearance) {
                let ratio = ContrastAuditTests.ratio(label: Palette.accentForeground,
                                                     on: surface.color, appearance)
                #expect(ratio >= ContrastAuditTests.textAA,
                        "accentForeground on \(surface.name) (\(appearance)) = \(ratio)")
            }
        }
    }

    /// The founder rule as a test: the roles only re-tune LIGHT. A dark value drifting off the
    /// bare accent would silently recolour approved dark looks.
    @Test("R4-TINT-03: both accent roles keep the bare accent's dark value")
    func darkValuesUnchanged() {
        for (name, pair) in [("accentFill", Palette.accentFill),
                             ("accentForeground", Palette.accentForeground)] {
            #expect(pair.dark == Palette.accent.dark, "\(name).dark must equal accent.dark")
        }
    }

    /// The play discs (Albums/Artists hover discs, the Recently Played now-playing disc) draw an
    /// `onAccent` glyph on an `accentFill` disc — a graphical object, so WCAG 1.4.11's 3:1. LIGHT
    /// is the binding case: `accentFill` deepens there, toward the near-black glyph.
    @Test("R4-TINT-04: an onAccent glyph clears non-text 3:1 on accentFill, both appearances")
    func glyphOnFill() {
        for appearance in TokenAppearance.allCases {
            let disc = Palette.accentFill.value(for: appearance)
                .over(Palette.window.value(for: appearance))
            let ratio = ContrastAuditTests.ratio(label: Palette.onAccent, on: disc, appearance)
            #expect(ratio >= ContrastAuditTests.nonTextAA, "onAccent on accentFill (\(appearance)) = \(ratio)")
        }
    }
}
