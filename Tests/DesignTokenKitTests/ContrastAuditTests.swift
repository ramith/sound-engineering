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
    static let textAA = 4.5
    /// Non-text contrast threshold (WCAG 1.4.11) — meter fills, indicator bars.
    static let nonTextAA = 3.0

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
    static func ratio(label: AppearancePair, on surface: RGBAColor,
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

    /// PR 6 (founder "split text vs fill", retires the light pins): the `status*Text` variants
    /// carry every text/glyph site (WCAG 4.5:1) — their LIGHT values are the dark red/amber
    /// that clear AA by design; DARK == the vivid value (already AA on the deep base). The
    /// vivid `statusError` is the meter-hot FILL (3:1 non-text — the "CLIP" word carries the
    /// meaning, A-M5, so the bar only needs to be visible). The vivid `statusWarning` is used
    /// ONLY as the decorative status dot (reinforcing adjacent text), so it is deliberately
    /// NOT audited at 3:1 here (it does not clear it on light, by design — the text beside it
    /// carries the meaning). History: the dark pairs promoted to hard assertions when the D10
    /// deep base (PR 2) lifted them; the old light-fails-AA pins are gone because vivid-as-text
    /// is gone.
    @Test("R4-LEG-03: status text variants clear AA + the error fill clears non-text, all surfaces")
    func statusLegibility() {
        let textTokens: [(name: String, pair: AppearancePair)] = [
            ("statusErrorText", Palette.statusErrorText),
            ("statusWarningText", Palette.statusWarningText),
        ]
        for appearance in TokenAppearance.allCases {
            for surface in Self.surfaces(appearance) {
                for token in textTokens {
                    let text = token.pair.value(for: appearance).over(surface.color)
                    #expect(RGBAColor.contrastRatio(text, surface.color) >= Self.textAA,
                            "\(token.name) on \(surface.name) (\(appearance)) < \(Self.textAA)")
                }
                let fill = Palette.statusError.value(for: appearance).over(surface.color)
                #expect(RGBAColor.contrastRatio(fill, surface.color) >= Self.nonTextAA,
                        "statusError fill on \(surface.name) (\(appearance)) < \(Self.nonTextAA)")
            }
        }
    }

    /// Design §7 R4 pair 4 — owed since PR 6, break-it caught the gap: the chrome device
    /// pill is a `.badge` fill over the WINDOW (the chrome band keeps the plain base, D4);
    /// its name is `label`, its rate readout `labelSecondary`. Both appearances, plus the
    /// RT/IC opaque composite the resolver serves.
    @Test("R4-CONTROL-01: device-pill text clears AA on the badge fill over the chrome band")
    func devicePillText() {
        for appearance in TokenAppearance.allCases {
            let window = Palette.window.value(for: appearance)
            let translucent = Palette.badgeFill.value(for: appearance).over(window)
            let opaque = Palette.badgeFill.value(for: appearance, increasedContrast: true).over(window)
            for (name, label) in [("label", Palette.label),
                                  ("labelSecondary", Palette.labelSecondary)] {
                for surface in [translucent, opaque] {
                    let ratio = Self.ratio(label: label, on: surface, appearance)
                    #expect(ratio >= Self.textAA, "\(name) on pill (\(appearance)) = \(ratio)")
                }
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
    static let glowGeometries: [(width: Double, height: Double)] = [(1120, 596), (880, 516)]

    /// Grid resolution — fine enough that a core (~250pt across) spans many samples.
    private static let gridColumns = 24
    private static let gridRows = 16

    static func gridPoints() -> [(x: Double, y: Double)] {
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
    /// Domain corrected at the break-it round: the original `x >= 0.5` guard modeled the
    /// pre-PR-5 50/50 split, but the restructure moved the queue to the LEFT flex region —
    /// where the teal core reaches — and jump-to-now-playing can center a tinted row
    /// anywhere in it. Rows are audited at EVERY grid point (a superset of reachable row
    /// positions — over-auditing is free, under-auditing was the hole).
    @Test("R4-GLOW-02: label clears AA on row tints over the queue region's glow field (dark)")
    func labelsOnRowTintsOverGlow() {
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() {
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

    // R4-GLOW-05 (card⊕glow, one pinned tertiary defect) was RETIRED in PR 5: the queue
    // pane's card fill is gone — rows sit directly on the glow field, which R4-GLOW-02
    // audits. The pin resolved by construction, not by waiver.

    // R4-GLOW-D8 (the sampled-palette corner audit) lives in its OWN suite at the bottom of
    // this file — the base suite sits at the type-body-length limit; the D8 suite shares
    // the fileprivate grid/ratio helpers so both audit the same geometry.

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

    // MARK: Hero badge composites (PR 4 — §7 R4 pair 5)

    /// Badge capsules sit on the glow field (the hero region — the TEAL core included, so
    /// this is the field's brightest text seat). RULE (the audit's third real catch,
    /// 2026-07-17): badge text is the PRIMARY `label` or a status color, NEVER the dimmed
    /// hierarchy — `labelSecondary` on badge⊕teal-core measures 4.26:1 (22 sampled points
    /// fail); the white badge fill brightens the backdrop exactly like the card⊕lime case.
    /// Hierarchy on a chip comes from the capsule, not from dimming its text.
    @Test("R4-BADGE-01: badge text clears AA on the badge fill over its real backdrops")
    func badgeTextOnBadges() {
        // PR 6 split: badge text is `label` or `statusWarningText` (the AA variant) — the
        // vivid `statusWarning` is only the path DOT (non-text, decorative reinforcement of
        // the adjacent label, so not audited at 3:1). This retires the light-badge pin.
        let texts: [(String, AppearancePair)] = [
            ("label", Palette.label),
            ("statusWarningText", Palette.statusWarningText),
        ]
        // Dark: badge ⊕ glow-field composite, sampled across the field.
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let badge = Palette.badgeFill.dark.over(glow)
                for (name, text) in texts {
                    let ratio = Self.ratio(label: text, on: badge, .dark)
                    #expect(ratio >= Self.textAA,
                            "\(name) on badge⊕glow @(\(point.x),\(point.y)) = \(ratio)")
                }
            }
        }
        // Light badge: both text colors clear AA outright now (statusWarningText's light value
        // is the dark amber sized for exactly this backdrop) — the pin is retired.
        let lightBadge = Palette.badgeFill.light.over(Palette.window.light)
        for (name, text) in texts {
            let ratio = Self.ratio(label: text, on: lightBadge, .light)
            #expect(ratio >= Self.textAA, "\(name) on light badge = \(ratio)")
        }
        for appearance in TokenAppearance.allCases {
            let opaque = Palette.badgeFill.value(for: appearance)
                .over(Palette.window.value(for: appearance))
            let ratio = Self.ratio(label: Palette.label, on: opaque, appearance)
            #expect(ratio >= Self.textAA, "label on opaque badge (\(appearance)) = \(ratio)")
        }
    }

    // MARK: Inspector panel composites (PR 5 — §7 R4 pair 3)

    /// The inspector fill sits over the glow field on the RIGHT side (never the teal core —
    /// the §3.3 placement rule's allowed domain), so tertiary is audited here too: the
    /// column is tertiary text's designed home.
    @Test("R4-PANEL-01: label hierarchy clears AA on the panel fill over its real backdrops")
    func labelsOnPanel() {
        let labels: [(String, AppearancePair)] = [
            ("label", Palette.label), ("labelSecondary", Palette.labelSecondary),
            ("labelTertiary", Palette.labelTertiary),
        ]
        for geometry in Self.glowGeometries {
            for point in Self.gridPoints() where point.x >= 0.5 {
                let glow = GlowFieldSpec.compositeBackdrop(
                    unitX: point.x, unitY: point.y,
                    containerWidth: geometry.width, containerHeight: geometry.height,
                    appearance: .dark
                )
                let panel = Palette.panelFill.dark.over(glow)
                for (name, label) in labels {
                    let ratio = Self.ratio(label: label, on: panel, .dark)
                    #expect(ratio >= Self.textAA,
                            "\(name) on panel⊕glow @(\(point.x),\(point.y)) = \(ratio)")
                }
            }
        }
        for appearance in TokenAppearance.allCases {
            let opaque = Palette.panelFill.value(for: appearance)
                .over(Palette.window.value(for: appearance))
            let lightDirect = appearance == .light
                ? Palette.panelFill.light.over(Palette.window.light) : opaque
            for (name, label) in labels {
                #expect(Self.ratio(label: label, on: opaque, appearance) >= Self.textAA,
                        "\(name) on opaque panel (\(appearance))")
                #expect(Self.ratio(label: label, on: lightDirect, appearance) >= Self.textAA,
                        "\(name) on light panel")
            }
        }
    }
}

// MARK: - Layout arithmetic (PR 5 — §7.1: the §5 width/height budget as assertions)

@Suite("Now Playing layout arithmetic (LAY)")
struct LayoutArithmeticTests {
    @Test("LAY-01: at the 880pt window minimum, queue and hero-left keep their minimum widths")
    func widthBudget() {
        let contentWidth = NowPlayingLayout.windowMinWidth - 2 * NowPlayingLayout.contentInset
        let queueWidth = contentWidth - NowPlayingLayout.regionGap - NowPlayingLayout.inspectorWidth
        #expect(queueWidth >= NowPlayingLayout.queueMinWidth,
                "queue gets \(queueWidth)pt at the minimum window")
        let heroLeft = contentWidth - NowPlayingLayout.regionGap - NowPlayingLayout.lensMinWidth
        #expect(heroLeft >= NowPlayingLayout.heroTextMinWidth,
                "hero text gets \(heroLeft)pt at the minimum window")
        #expect(NowPlayingLayout.lensMaxWidth >= NowPlayingLayout.lensMinWidth)
    }

    @Test("LAY-02: the hero row never starves the queue at the minimum window, max type included")
    func heightBudget() {
        let content = NowPlayingLayout.windowMinHeight
            - NowPlayingLayout.chromeHeight - NowPlayingLayout.footerHeight
        // Hero row height = the lens (its fixed height dominates the text block at default
        // type) + vertical padding; the type headroom factor absorbs Dynamic-Type growth of
        // the title/badge block past the lens height (§7.1 documented approximation).
        let heroRow = (NowPlayingLayout.lensHeight + NowPlayingLayout.contentInset + 12)
            * NowPlayingLayout.maxTypeHeadroom
        let queueRegion = content - heroRow - NowPlayingLayout.contentInset
        let minVisibleRows = 5.0
        let rowHeight = 36.0 // SongsList.rowHeight-class row
        #expect(queueRegion >= minVisibleRows * rowHeight,
                "queue region \(queueRegion)pt < \(minVisibleRows) rows at max type")
    }
}

// MARK: - D8 sampled-corner audit (own suite — the base suite is at the type-length limit)

/// D8 (PR 7): the art-sampled worst case. Every sampled color is clamped into a per-slot
/// channel-ceiling box with the slot's token alpha forced. PER SLOT, the box corner
/// (ceiling-gray at token alpha) dominates every SAMPLED color — sRGB compositing and
/// relative luminance are monotone in source channels — and the slot's other reachable
/// state is the BRAND fallback, which the corner does NOT dominate (review MAJOR-2: brand
/// teal's green/blue exceed the 0.62 teal ceiling; brand blue's blue channel exceeds its
/// 0.95 corner). So the audit folds EVERY per-slot {corner, brand} combination — 2³ masks —
/// which exactly covers the reachable palette union by per-slot monotonicity. Pairs match
/// R4-GLOW-01/02/04 plus the lens/badge/panel composites that sit over the field (§7 R4
/// table). The all-brand mask duplicates the concrete R4-GLOW tests — kept for the
/// lattice's completeness argument.
@Suite("Contrast audit — sampled glow corner (R4-GLOW-D8)")
struct SampledCornerAuditTests {
    @Test("R4-GLOW-D8: every {corner, brand} fallback-lattice fold clears every pair (dark)")
    func sampledCornerLatticeOnGlowField() {
        let corner = SampledGlow.auditCornerPalette
        let slotCount = GlowFieldSpec.glows.count
        for mask in 0 ..< (1 << slotCount) {
            let palette: [RGBAColor?] = (0 ..< slotCount).map { slot in
                (mask & (1 << slot)) == 0 ? corner[slot] : nil // nil ⇒ the brand token
            }
            for geometry in ContrastAuditTests.glowGeometries {
                for point in ContrastAuditTests.gridPoints() {
                    let backdrop = GlowFieldSpec.compositeBackdrop(
                        unitX: point.x, unitY: point.y,
                        containerWidth: geometry.width, containerHeight: geometry.height,
                        appearance: .dark, overrideColors: palette
                    )
                    assertPairs(on: backdrop, point: point, geometry: geometry)
                }
            }
        }
    }

    private func assertPairs(on backdrop: RGBAColor, point: (x: Double, y: Double),
                             geometry: (width: Double, height: Double)) {
        let textAA = ContrastAuditTests.textAA
        // R4-GLOW-01 pairs: label + secondary everywhere.
        for (name, label) in [("label", Palette.label),
                              ("labelSecondary", Palette.labelSecondary)] {
            let ratio = ContrastAuditTests.ratio(label: label, on: backdrop, .dark)
            #expect(ratio >= textAA, "\(name) @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
        }
        // R4-GLOW-04 pair: tertiary outside the teal core (same placement rule).
        let tealT = GlowFieldSpec.tealDistance(unitX: point.x, unitY: point.y,
                                               containerWidth: geometry.width,
                                               containerHeight: geometry.height)
        if tealT > GlowFieldSpec.falloffMidStop {
            let ratio = ContrastAuditTests.ratio(label: Palette.labelTertiary, on: backdrop, .dark)
            #expect(ratio >= textAA,
                    "labelTertiary @(\(point.x),\(point.y)) \(geometry.width)pt = \(ratio)")
        }
        // R4-GLOW-02 pairs: row tints — EVERY point (post-PR-5 the queue is the LEFT flex
        // region, reaching the teal core; the old x >= 0.5 guard was the audit's stale hole).
        for (name, tint) in [("rowNowPlaying", Palette.rowNowPlaying),
                             ("rowSelected", Palette.rowSelected)] {
            let tinted = tint.dark.over(backdrop)
            let ratio = ContrastAuditTests.ratio(label: Palette.label, on: tinted, .dark)
            #expect(ratio >= textAA, "label on \(name) @(\(point.x),\(point.y)) = \(ratio)")
        }
        // Lens + badge fills sit over the field: their text pairs at the corner too.
        let lens = Palette.lensFill.dark.over(backdrop)
        for (name, label) in [("label", Palette.label),
                              ("labelSecondary", Palette.labelSecondary)] {
            let ratio = ContrastAuditTests.ratio(label: label, on: lens, .dark)
            #expect(ratio >= textAA, "\(name) on lens⊕corner @(\(point.x),\(point.y)) = \(ratio)")
        }
        let badge = Palette.badgeFill.dark.over(backdrop)
        for (name, label) in [("label", Palette.label),
                              ("statusWarningText", Palette.statusWarningText)] {
            let ratio = ContrastAuditTests.ratio(label: label, on: badge, .dark)
            #expect(ratio >= textAA, "\(name) on badge⊕corner @(\(point.x),\(point.y)) = \(ratio)")
        }
        // R4-PANEL-01 pairs (review MAJOR-3): the inspector panel renders over the field on
        // the RIGHT side — tertiary text's designed home (§3.3 placement rule), so ALL three
        // label rungs are audited on panel⊕field there. The bottom BLEED stratum is NOT a
        // text surface: folding it measured tertiary at 4.18 (break-it catch), so the
        // constraint is ENCODED instead of diluted — `InspectorColumn`'s bottom content
        // inset IS `GlassDecor.bleedHeight` (same token, cannot drift), meaning text never
        // RESTS on the bleed run; transient scroll crossings are accepted (the seam-feather
        // class).
        if point.x >= 0.5 {
            let panel = Palette.panelFill.dark.over(backdrop)
            for (name, label) in [("label", Palette.label),
                                  ("labelSecondary", Palette.labelSecondary),
                                  ("labelTertiary", Palette.labelTertiary)] {
                let ratio = ContrastAuditTests.ratio(label: label, on: panel, .dark)
                #expect(ratio >= textAA, "\(name) on panel⊕corner @(\(point.x),\(point.y)) = \(ratio)")
            }
        }
    }
}
