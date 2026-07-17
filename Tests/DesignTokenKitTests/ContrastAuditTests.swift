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

    // GEOMETRIC MODEL (v2, per the PR-2 design review "Option B"): the audit SAMPLES the
    // REAL three-glow composite from `GlowFieldSpec.compositeBackdrop` on a grid, at the
    // reference tab geometry AND the min-window geometry (overlaps grow as the container
    // shrinks). This replaced an abstract cores+overlaps model whose worst cases were
    // geometrically impossible — and it re-verifies AUTOMATICALLY whenever the founder
    // tunes glow centers, because render and audit read the same Kit data.
    //
    // DARK ONLY: the resolver suppresses the glow field outside dark appearance (RES-04),
    // so light pairs would audit pixels that never render.
    //
    // PLACEMENT RULE (§3.3, unchanged): labelTertiary small text never sits inside the
    // TEAL core (t ≤ midStop) — the 8a mock puts only the HERO (large text, 3:1) there.
    // Full-alpha teal × tertiary measures 3.98:1 — the number that forced the rule.

    /// Tab geometries to sample: (reference 1120×596, min-window 880×516 content region).
    private static let glowGeometries: [(width: Double, height: Double)] = [(1120, 596), (880, 516)]

    /// Grid resolution — fine enough that a core (~250pt across) spans many samples.
    private static let gridColumns = 24
    private static let gridRows = 16

    private static func gridPoints() -> [(x: Double, y: Double)] {
        (0 ... gridRows).flatMap { row in
            (0 ... gridColumns).map { column in
                (Double(column) / Double(gridColumns), Double(row) / Double(gridRows))
            }
        }
    }

    /// Pair 1a: label + labelSecondary clear AA at EVERY sampled point of the real glow
    /// field — no placement restriction on primary/secondary text.
    @Test("R4-GLOW-01: label + labelSecondary clear AA across the sampled glow field (dark)")
    func primaryLabelsOnGlowField() {
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() {
                let backdrop = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = Self.ratio(label: label, on: backdrop, .dark)
                    #expect(ratio >= Self.textAA,
                            "\(name) @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
                }
            }
        }
    }

    /// Pair 1b: labelTertiary clears AA at every sampled point OUTSIDE the teal core (its
    /// placement rule's whole allowed domain).
    @Test("R4-GLOW-04: labelTertiary clears AA everywhere outside the teal core (dark)")
    func tertiaryOnGlowField() {
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() {
                let tealT = GlowFieldSpec.tealDistance(unitX: point.x, unitY: point.y,
                                                       containerWidth: geometry.width,
                                                       containerHeight: geometry.height)
                guard tealT > GlowFieldSpec.falloffMidStop else { continue }
                let backdrop = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let ratio = Self.ratio(label: Palette.labelTertiary, on: backdrop, .dark)
                #expect(ratio >= Self.textAA,
                        "labelTertiary @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
            }
        }
    }

    /// Pair 6: queue-row tints over the glow field. The queue occupies the RIGHT region
    /// (today's 50/50 pane; post-PR-5 queue-flex) — never the top-left teal core.
    @Test("R4-GLOW-02: label clears AA on row tints over the queue region's glow field (dark)")
    func labelsOnRowTintsOverGlow() {
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() where point.x >= 0.5 {
                let backdrop = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                for (name, tint) in [("rowNowPlaying", Palette.rowNowPlaying),
                                     ("rowSelected", Palette.rowSelected)] {
                    let tinted = tint.value(for: .dark).over(backdrop)
                    let ratio = Self.ratio(label: Palette.label, on: tinted, .dark)
                    #expect(ratio >= Self.textAA,
                            "label on \(name) @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
                }
            }
        }
    }

    /// PR-2 review MAJOR 5: the right pane paints `card` OVER the glow field until PR 5
    /// restyles the panes — the white veil BRIGHTENS the backdrop. label/labelSecondary
    /// must clear AA on the card⊕glow composite outright; tertiary FAILS near the lime
    /// core today (measured 4.23) — one defect, pinned as one known issue, resolved by
    /// the PR-5 pane restyle (the 8a inspector glass darkens instead of brightening).
    @Test("R4-GLOW-05: labels on card⊕glow (interim pane); tertiary pinned to PR 5")
    func labelsOnCardOverGlow() {
        var worstTertiary = Double.infinity
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() where point.x >= 0.5 {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let backdrop = Palette.card.dark.over(glow)
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = Self.ratio(label: label, on: backdrop, .dark)
                    #expect(ratio >= Self.textAA,
                            "\(name) on card⊕glow @(\(point.x),\(point.y)) = \(ratio)")
                }
                worstTertiary = min(worstTertiary,
                                    Self.ratio(label: Palette.labelTertiary, on: backdrop, .dark))
            }
        }
        withKnownIssue("tertiary on card⊕glow (queue pane over the lime core) — interim until the PR-5 pane restyle") {
            #expect(worstTertiary >= Self.textAA)
        }
    }

    // MARK: Lens composites (PR 3 — §7 R4 pair 2)

    /// The lens fill sits over the glow field; its future axis text (PR 5) and any in-lens
    /// labels must clear AA on the fill⊕glow composite — sampled across the field in dark
    /// (the lens is currently full-width; the D6 frame narrows it in PR 5, a subset of
    /// these points). Light: the lens is white-glass over the plain light window. RT/IC:
    /// the resolver's OPAQUE fallback is audited explicitly.
    @Test("R4-LENS-01: label hierarchy clears AA on the lens fill over its real backdrops")
    func labelsOnLens() {
        // Dark: lens ⊕ glow-field composite, sampled.
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let lens = Palette.lensFill.dark.over(glow)
                for (name, label) in [("label", Palette.label),
                                      ("labelSecondary", Palette.labelSecondary)] {
                    let ratio = Self.ratio(label: label, on: lens, .dark)
                    #expect(ratio >= Self.textAA,
                            "\(name) on lens⊕glow @(\(point.x),\(point.y)) = \(ratio)")
                }
            }
        }
        // Light: lens over the plain window (glows are suppressed in light).
        let lightLens = Palette.lensFill.light.over(Palette.window.light)
        for (name, label) in [("label", Palette.label), ("labelSecondary", Palette.labelSecondary)] {
            let ratio = Self.ratio(label: label, on: lightLens, .light)
            #expect(ratio >= Self.textAA, "\(name) on light lens = \(ratio)")
        }
        // RT/IC opaque fallbacks, both appearances.
        for appearance in TokenAppearance.allCases {
            let opaque = Palette.lensFill.value(for: appearance)
                .over(Palette.window.value(for: appearance))
            for (name, label) in [("label", Palette.label), ("labelSecondary", Palette.labelSecondary)] {
                let ratio = Self.ratio(label: label, on: opaque, appearance)
                #expect(ratio >= Self.textAA, "\(name) on opaque lens (\(appearance)) = \(ratio)")
            }
        }
    }
}
