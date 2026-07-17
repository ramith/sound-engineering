// R4 — the PERMANENT contrast audit (design §7 R4): pure sRGB compositing + WCAG math over
// Kit token data, so "the palette is legible" is a forever-green `swift test` fact, not a
// one-off audit. PR 1a scope = the LEGACY pairs (window/card/panel × label hierarchy — the
// D10 net: when PR 2 re-bases the dark stack, these pairs re-verify the untouched tabs by
// math). Glow/lens/panel-role composites join in PRs 2–5 per the §7 R4 pair table.
//
// Thresholds are the WCAG constants, never tuned: ≥ 4.5:1 text AA; ≥ 3.0:1 non-text.

import DesignTokenKit
import Testing

@Suite("Contrast audit — legacy surfaces (R4)")
struct ContrastAuditTests {
    /// AA threshold for text (WCAG 1.4.3).
    private static let textAA = 4.5

    /// The surfaces labels sit on today: the window itself, and card/panel composited over
    /// the window (they are translucent in dark mode — compositing IS the audit's point).
    private static func surfaces(_ appearance: TokenAppearance) -> [(name: String, color: RGBAColor)] {
        let window = Palette.window.value(for: appearance)
        return [
            ("window", window),
            ("card⊕window", Palette.card.value(for: appearance).over(window)),
            ("panel⊕window", Palette.panel.value(for: appearance).over(window)),
        ]
    }

    /// Effective text color = the (translucent) label composited onto its surface; the
    /// ratio is then between two opaque colors, per WCAG method.
    private static func ratio(label: AppearancePair, on surface: RGBAColor,
                              _ appearance: TokenAppearance) -> Double {
        let text = label.value(for: appearance).over(surface)
        return RGBAColor.contrastRatio(text, surface)
    }

    @Test("R4-LEG-01: label + labelSecondary clear AA on window/card/panel, both appearances")
    func primaryAndSecondaryLabels() {
        for appearance in TokenAppearance.allCases {
            for surface in Self.surfaces(appearance) {
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = Self.ratio(label: label, on: surface.color, appearance)
                    #expect(ratio >= Self.textAA,
                            "\(name) on \(surface.name) (\(appearance)) = \(ratio) < \(Self.textAA)")
                }
            }
        }
    }

    /// The S9 audit lifted tertiary for this — but it measured against the WINDOW, not the
    /// translucent card/panel COMPOSITES. The audit's first real find (PR 1a, 2026-07-17):
    /// tertiary on panel⊕window at the OLD #1E1E1E base was 4.4601:1. The D10 deep-base
    /// re-tune (PR 2) fixed it — the pin flipped "unexpectedly passed" on the first run
    /// against #0e1013 and was PROMOTED to the hard assertion below (the design §7 R4
    /// mechanism working as written).
    @Test("R4-LEG-02: labelTertiary clears AA on window/card/panel, both appearances")
    func tertiaryLabel() {
        for appearance in TokenAppearance.allCases {
            for surface in Self.surfaces(appearance) {
                let ratio = Self.ratio(label: Palette.labelTertiary, on: surface.color, appearance)
                #expect(ratio >= Self.textAA,
                        "labelTertiary on \(surface.name) (\(appearance)) = \(ratio) < \(Self.textAA)")
            }
        }
    }

    /// statusError aliases the shipped Color.red look (macOS-26 palette-red values). History:
    /// at the OLD #1E1E1E base only the dark WINDOW pair cleared AA (dark card/panel were
    /// 4.28/4.09) — the D10 deep base (PR 2) flipped BOTH dark pins "unexpectedly passed"
    /// and they were promoted to hard assertions below. The three LIGHT pairs (≈3.05–3.57)
    /// stay individually pinned (the light palette is untouched until the PR-6 meters/footer
    /// restyle — a token-value fix).
    @Test("R4-LEG-03: statusError clears AA on ALL dark surfaces; light pinned to PR 6")
    func statusErrorText() {
        // Dark: every surface must pass outright on the deep base (promoted from pins, PR 2).
        for surface in Self.surfaces(.dark) {
            let text = Palette.statusError.dark.over(surface.color)
            let ratio = RGBAColor.contrastRatio(text, surface.color)
            #expect(ratio >= Self.textAA,
                    "statusError on \(surface.name) (dark) = \(ratio) < \(Self.textAA)")
        }
        // Light: pre-existing shortfalls — tracked PER PAIR (a partial fix must flip its own
        // pair loud), not silently passed, not silently fixed.
        for surface in Self.surfaces(.light) {
            let text = Palette.statusError.light.over(surface.color)
            let ratio = RGBAColor.contrastRatio(text, surface.color)
            withKnownIssue("statusError light/\(surface.name) fails AA — pre-existing; PR-6 restyle") {
                #expect(ratio >= Self.textAA)
            }
        }
    }

    // MARK: Glow-field composites (PR 2 — §7 R4 pairs 1 + 6)

    // MODEL (geometry-refined after the first run failed 9 pairs at naive full-alpha-
    // everywhere — the audit's first catch on NEW work, 2026-07-17):
    //   * SINGLE-glow cores at token MAX alpha — small text genuinely can sit on a core.
    //   * PAIRWISE overlaps at the MID-STOP attenuation (falloffMidAlphaFactor of peak) —
    //     the three core regions are geometrically disjoint (teal top-left, lime bottom-
    //     right, blue mid-right); only the faded tails overlap, and mid-stop-×-mid-stop is
    //     still conservative versus the real tail-×-tail.
    //   * PLACEMENT RULE (the 8a mock's own behavior — its CSS puts only the HERO, large
    //     text at 3:1, over the teal core): labelTertiary small text must NEVER sit inside
    //     the TEAL core. Encoded here as: tertiary is audited at max alpha on lime/blue
    //     cores + everywhere-attenuated, and at MID-STOP on teal. Review owns keeping
    //     tertiary text out of the top-left core (post-PR-5 all tertiary lives in the
    //     inspector, right side). Full-alpha teal × tertiary measures 3.98:1 dark — the
    //     number that forced this rule; a waiver was not taken, a placement constraint was.

    private static let glowPairs = [("teal", Palette.glowTeal), ("lime", Palette.glowLime),
                                    ("blue", Palette.glowBlue)]

    private static func attenuated(_ pair: AppearancePair, _ appearance: TokenAppearance) -> RGBAColor {
        let value = pair.value(for: appearance)
        return value.opacity(value.alpha * GlowFieldSpec.falloffMidAlphaFactor)
    }

    /// Single cores at MAX alpha (for label/labelSecondary; lime/blue also for tertiary).
    private static func coreBackdrops(_ appearance: TokenAppearance) -> [(name: String, color: RGBAColor)] {
        let window = Palette.window.value(for: appearance)
        return glowPairs.map { name, pair in
            ("core:\(name)", pair.value(for: appearance).over(window))
        }
    }

    /// Pairwise overlaps at mid-stop attenuation + the teal core at mid-stop (the tertiary
    /// placement rule's audited surface).
    private static func attenuatedBackdrops(_ appearance: TokenAppearance) -> [(name: String, color: RGBAColor)] {
        let window = Palette.window.value(for: appearance)
        var backdrops: [(String, RGBAColor)] = [
            ("mid:teal", attenuated(Palette.glowTeal, appearance).over(window)),
        ]
        for first in 0 ..< glowPairs.count {
            for second in (first + 1) ..< glowPairs.count {
                let composite = attenuated(glowPairs[second].1, appearance)
                    .over(attenuated(glowPairs[first].1, appearance).over(window))
                backdrops.append(("mid:\(glowPairs[first].0)⊕\(glowPairs[second].0)", composite))
            }
        }
        return backdrops
    }

    /// Pair 1a: label + labelSecondary clear AA on EVERY core at max alpha and every
    /// attenuated overlap — no placement restriction on primary/secondary text.
    @Test("R4-GLOW-01: label + labelSecondary clear AA on all cores and overlaps")
    func primaryLabelsOnGlowField() {
        for appearance in TokenAppearance.allCases {
            let backdrops = Self.coreBackdrops(appearance) + Self.attenuatedBackdrops(appearance)
            for backdrop in backdrops {
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = Self.ratio(label: label, on: backdrop.color, appearance)
                    #expect(ratio >= Self.textAA,
                            "\(name) on \(backdrop.name) (\(appearance)) = \(ratio) < \(Self.textAA)")
                }
            }
        }
    }

    /// Pair 1b: labelTertiary under the placement rule — lime/blue cores at max, teal at
    /// mid-stop, all overlaps attenuated.
    @Test("R4-GLOW-04: labelTertiary clears AA everywhere its placement rule allows")
    func tertiaryOnGlowField() {
        for appearance in TokenAppearance.allCases {
            let allowed = Self.coreBackdrops(appearance).filter { $0.name != "core:teal" }
                + Self.attenuatedBackdrops(appearance)
            for backdrop in allowed {
                let ratio = Self.ratio(label: Palette.labelTertiary, on: backdrop.color, appearance)
                #expect(ratio >= Self.textAA,
                        "labelTertiary on \(backdrop.name) (\(appearance)) = \(ratio) < \(Self.textAA)")
            }
        }
    }

    /// Pair 6: queue-row tints over the glow field (post-PR-5 the queue sits centre-right —
    /// lime/blue cores + attenuated everything; never the top-left teal core).
    @Test("R4-GLOW-02: label clears AA on row tints over the queue's glow backdrops")
    func labelsOnRowTintsOverGlow() {
        for appearance in TokenAppearance.allCases {
            let backdrops = Self.coreBackdrops(appearance).filter { $0.name != "core:teal" }
                + Self.attenuatedBackdrops(appearance)
            for backdrop in backdrops {
                for (name, tint) in [("rowNowPlaying", Palette.rowNowPlaying),
                                     ("rowSelected", Palette.rowSelected)] {
                    let tinted = tint.value(for: appearance).over(backdrop.color)
                    let ratio = Self.ratio(label: Palette.label, on: tinted, appearance)
                    #expect(ratio >= Self.textAA,
                            "label on \(name)⊕\(backdrop.name) (\(appearance)) = \(ratio) < \(Self.textAA)")
                }
            }
        }
    }
}
