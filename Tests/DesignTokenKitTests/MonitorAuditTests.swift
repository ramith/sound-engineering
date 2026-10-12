// R4-MON — Monitoring's BEFORE / AFTER colours (S10.8 F1, decision 4), on the lenses G1 puts each channel
// on. Own file, same posture as R4-SPEC / R4-EQ: it shares the thresholds, the glow grid and the ratio
// helper with the base R4 suite.
//
// The tab sits on the app glow. Each channel is an analyzer lens (`.lens`: translucent over the glow, its
// opaque composite under Reduce Transparency and Increase Contrast, the dark bleed along its bottom), and
// the header (title, legend) sits on the bare glow. Each colour is audited on every backdrop it can meet —
// at every sampled point of the glow, and on the plain window Reduce Transparency and Increase Contrast
// leave (the glow off) — in both appearances.
//
// Not audited, and why:
// - the idle dim (the bars at 25% while nothing plays), like the analyzer's paused dim (R4-SPEC): a
//   decorative exemption — the row's VoiceOver value carries its state; the bars are hidden;
// - the next lens's drop shadow: lenses stack, and each one's shadow reaches up under the lens above it.
//   In dark it only darkens that lens's backdrop, which lifts every ratio here (the marks are lighter
//   than it); in light the shadow (8 pt, 3 pt down) dies out inside the 12 pt gap.

import DesignTokenKit
import Testing

@Suite("Contrast audit — Monitoring's BEFORE / AFTER colours on the lens (R4-MON)")
struct MonitorAuditTests {
    /// One composited backdrop a colour can sit on.
    private typealias Backdrop = (name: String, color: RGBAColor)
    /// One appearance column of the audit.
    private typealias Column = (appearance: TokenAppearance, increasedContrast: Bool)

    /// Both appearances, plain and Increase Contrast.
    private static let columns: [Column] =
        TokenAppearance.allCases.flatMap { appearance in [(appearance, false), (appearance, true)] }

    /// AFTER's bar positions: a dense grid (every 1/129 — the monitor's 44 bars sit on every third
    /// point) plus every ramp stop.
    private static let positions: [Float] =
        (0 ... 129).map { Float($0) / 129 } + SpectrumRamp.stops.map(\.position)

    /// The bare backdrop in `column`: the app glow at every sampled point of both reference sizes, or —
    /// under Increase Contrast, which brings Reduce Transparency and so drops the glow — the window alone.
    /// The plain window is in both lists (Reduce Transparency alone also drops the glow).
    private static func bareBackdrops(_ column: Column) -> [Backdrop] {
        let window = Palette.window.value(for: column.appearance, increasedContrast: column.increasedContrast)
        var backdrops: [Backdrop] = [("window", window)]
        guard !column.increasedContrast else { return backdrops }
        for geometry in ContrastAuditTests.glowGeometries {
            for point in ContrastAuditTests.gridPoints() {
                backdrops.append(("glow @(\(point.x),\(point.y)) \(geometry.width)pt",
                                  GlowFieldSpec.compositeBackdrop(
                                      unitX: point.x, unitY: point.y,
                                      containerWidth: geometry.width, containerHeight: geometry.height,
                                      appearance: column.appearance, glows: GlowFieldSpec.appGlows
                                  )))
            }
        }
        return backdrops
    }

    /// Every lens a channel can be drawn on in `column`: the translucent lens over every bare backdrop (a
    /// lens can be at any height — one to eight channels, scrolling — so every point of the glow counts),
    /// and the opaque composite the resolver serves under Reduce Transparency. Increase Contrast has that
    /// opaque lens alone.
    private static func lenses(_ column: Column) -> [Backdrop] {
        var lenses: [Backdrop] = []
        if case let .fill(opaque) = resolveSurface(role: .lens, appearance: column.appearance,
                                                   reduceTransparency: true,
                                                   increasedContrast: column.increasedContrast) {
            lenses.append(("opaque lens", opaque))
        }
        guard !column.increasedContrast else { return lenses }
        let fill = Palette.lensFill.value(for: column.appearance)
        return lenses + bareBackdrops(column).map { ("lens⊕\($0.name)", fill.over($0.color)) }
    }

    /// The lenses in `column` where the bars' foot meets the dark bleed: `lensPadding` above the lens's
    /// bottom edge, the bleed at its strength there (dark only — light has no bleed; the opaque lens
    /// keeps it too, as `.glassPanel` draws it over every dark fill).
    private static func bleedLenses(_ column: Column) -> [Backdrop] {
        guard column.appearance == .dark else { return [] }
        let reach = max(0, min(1, (GlassDecor.bleedHeight - MonitorLayout.lensPadding) / GlassDecor.bleedHeight))
        let bleed = GlassDecor.bleedDark.opacity(GlassDecor.bleedDark.alpha * reach)
        return lenses(column).map { ("\($0.name) ⊕ bleed", bleed.over($0.color)) }
    }

    /// Asserts `mark` (composited onto each backdrop) clears `threshold` on every one.
    private static func expect(_ name: String, _ mark: AppearancePair, on backdrops: [Backdrop],
                               _ threshold: Double, _ column: Column) {
        let color = mark.value(for: column.appearance, increasedContrast: column.increasedContrast)
        for backdrop in backdrops {
            let ratio = RGBAColor.contrastRatio(color.over(backdrop.color), backdrop.color)
            #expect(ratio >= threshold, "\(name) on \(backdrop.name) \(column) = \(ratio)")
        }
    }

    @Test("R4-MON-01: the bars clear non-text 3:1 on the lens — BEFORE's grey, AFTER's ramp (playing)")
    func barsOnLens() {
        for column in Self.columns {
            let lenses = Self.lenses(column)
            Self.expect("beforeFill", MonitorPalette.beforeFill, on: lenses, ContrastAuditTests.nonTextAA, column)
            for position in Self.positions {
                Self.expect("afterFill @\(position)", MonitorPalette.afterFill(at: position), on: lenses,
                            ContrastAuditTests.nonTextAA, column)
            }
        }
    }

    /// The bars grow from `lensPadding` above the lens's bottom edge, inside the dark bleed's band (the
    /// lens keeps it — founder, S10.8 part 2), so every bar's foot meets the bleed at that height.
    @Test("R4-MON-01b: the bars clear 3:1 at their foot, where the dark lens's bottom bleed reaches them")
    func barsOnBottomBand() {
        #expect(MonitorLayout.lensPadding < GlassDecor.bleedHeight, "the bars' foot sits inside the bleed band")
        for column in Self.columns {
            let lenses = Self.bleedLenses(column)
            Self.expect("beforeFill", MonitorPalette.beforeFill, on: lenses, ContrastAuditTests.nonTextAA, column)
            for position in Self.positions {
                Self.expect("afterFill @\(position)", MonitorPalette.afterFill(at: position), on: lenses,
                            ContrastAuditTests.nonTextAA, column)
            }
        }
    }

    @Test("R4-MON-02: the legend swatches clear non-text 3:1 on the header's backdrop (the bare glow)")
    func legendSwatches() {
        for column in Self.columns {
            let backdrops = Self.bareBackdrops(column)
            Self.expect("beforeFill swatch", MonitorPalette.beforeFill, on: backdrops,
                        ContrastAuditTests.nonTextAA, column)
            for position in Self.positions {
                Self.expect("afterFill swatch @\(position)", MonitorPalette.afterFill(at: position),
                            on: backdrops, ContrastAuditTests.nonTextAA, column)
            }
        }
    }

    /// The tags are TEXT (AA), so they take their side's text colour, not the bars' fill. The channel
    /// name beside them (`label`) is audited too: it is the row's other text. The tag line sits at the
    /// lens's top, above the bleed's band even on the shortest lens (asserted), so the plain lens is theirs.
    @Test("R4-MON-03: the BEFORE / AFTER tags and the channel name clear AA on the lens")
    func tagsOnLens() {
        let tagLineBottom = MonitorLayout.rowMinHeight - MonitorLayout.lensPadding - MonitorLayout.tagLineHeight
        #expect(tagLineBottom >= GlassDecor.bleedHeight, "the tag line clears the bleed on the shortest lens")
        let texts: [(String, AppearancePair)] = [
            ("beforeText", MonitorPalette.beforeText), ("afterText", MonitorPalette.afterText),
            ("label", Palette.label),
        ]
        for column in Self.columns {
            let lenses = Self.lenses(column)
            for (name, text) in texts {
                Self.expect(name, text, on: lenses, ContrastAuditTests.textAA, column)
            }
        }
    }

    /// Decision 4 as a test: BEFORE is a neutral grey (equal channels, both appearances) and AFTER is the
    /// analyzer's own ramp, value for value — so a ramp re-tune moves the monitor with it.
    @Test("R4-MON-04: BEFORE is a neutral grey; AFTER is the analyzer ramp")
    func decisionFour() {
        for appearance in TokenAppearance.allCases {
            let grey = MonitorPalette.beforeFill.value(for: appearance)
            #expect(grey.red == grey.green && grey.green == grey.blue, "beforeFill is not grey (\(appearance))")
        }
        for position in Self.positions {
            #expect(MonitorPalette.afterFill(at: position) == SpectrumRamp.color(at: position))
        }
    }
}
