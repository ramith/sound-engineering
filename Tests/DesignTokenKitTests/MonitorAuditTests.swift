// R4-MON — Monitoring's BEFORE / AFTER colours (S10.8 F1, decision 4). Own file, same posture as
// R4-SPEC / R4-EQ: it shares the thresholds, the glow grid and the ratio helper with the base R4 suite.
//
// Since F1 the tab sits on the app glow: the channel rows' `card` fill (translucent in dark) shows the
// glow through, and the header (title, legend) sits on the bare glow. Each colour is audited on every
// backdrop it can meet — at every sampled point of the glow, and on the plain window Reduce Transparency
// and Increase Contrast leave (the glow off) — in both appearances.
//
// Decorative exemption — NOT audited: the idle dim (the bars at 25% while nothing plays), like the
// analyzer's paused dim (R4-SPEC). The row's VoiceOver label carries its state; the bars are hidden.

import DesignTokenKit
import Testing

@Suite("Contrast audit — Monitoring's BEFORE / AFTER colours (R4-MON)")
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

    /// The channel row's card over every bare backdrop: where the bars and tags sit. A row can be at
    /// any height (one to eight channels, scrolling), so every point of the glow counts.
    private static func rowCards(_ column: Column) -> [Backdrop] {
        let card = Palette.card.value(for: column.appearance, increasedContrast: column.increasedContrast)
        return bareBackdrops(column).map { ("card⊕\($0.name)", card.over($0.color)) }
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

    @Test("R4-MON-01: the bars clear non-text 3:1 on the row card — BEFORE's grey, AFTER's ramp (playing)")
    func barsOnRowCard() {
        for column in Self.columns {
            let cards = Self.rowCards(column)
            Self.expect("beforeFill", MonitorPalette.beforeFill, on: cards, ContrastAuditTests.nonTextAA, column)
            for position in Self.positions {
                Self.expect("afterFill @\(position)", MonitorPalette.afterFill(at: position), on: cards,
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
    /// name beside them (`label`) is audited too: it is the row's other text over the glow.
    @Test("R4-MON-03: the BEFORE / AFTER tags and the channel name clear AA on the row card")
    func tagsOnRowCard() {
        let texts: [(String, AppearancePair)] = [
            ("beforeText", MonitorPalette.beforeText), ("afterText", MonitorPalette.afterText),
            ("label", Palette.label),
        ]
        for column in Self.columns {
            let cards = Self.rowCards(column)
            for (name, text) in texts {
                Self.expect(name, text, on: cards, ContrastAuditTests.textAA, column)
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
