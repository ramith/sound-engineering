// LAY-EQ-01 — the EQ rail's height budget (UI plan §5.6), Tone card part (EQ3t). The budget is the
// window − chrome − footer − the screen's rail insets: 556 pt at 1000×720, 476 pt at 880×640. The
// Tone card's heights come from `EQLayout`, which the card lays out from; the Equalizer card's is
// the prototype's measure until EQ3 lands its own `EQLayout` arithmetic beside these.

import DesignTokenKit
import Testing

@Suite("EQ layout — the rail's height budget (LAY-EQ-01, Tone)")
struct EQLayoutTests {
    /// The EQ screen's insets above and below the rail (UI plan §5.6: Library's 22 / 18).
    private static let railInsets = 22.0 + 18.0
    /// Between the Equalizer card and the Tone card.
    private static let cardGap = 12.0
    /// The Equalizer card with 7 built-ins + 2 My Presets at 28 pt rows: the prototype measured both
    /// cards at 553 of 556 pt with a 185 pt Tone card (553 − 185 − 12).
    private static let equalizerCardHeight = 356.0
    /// The rail's width (`DesignSystem.LayoutMetrics.sidebarIdeal`, shared with the Library).
    private static let railWidth = 234.0
    /// The five Tone regions (decision 24).
    private static let toneRows = 5

    private static func railBudget(windowHeight: Double) -> Double {
        windowHeight - NowPlayingLayout.chromeHeight - NowPlayingLayout.footerHeight - railInsets
    }

    @Test("LAY-EQ-01a: the Tone card is one line folded, and five 29 pt rows more open")
    func toneCardHeights() {
        let folded = EQLayout.toneCardHeight(rows: 0)
        let open = EQLayout.toneCardHeight(rows: Self.toneRows)
        #expect(folded == 2 * EQLayout.toneCardPadding + EQLayout.toneHeaderHeight)
        #expect(open == folded + EQLayout.toneHeaderGap + Double(Self.toneRows) * EQLayout.toneRowHeight)
        #expect(EQLayout.toneRowHeight == 29, "the plan's row height")
        #expect(folded <= 40, "folded, the card is the one line the 880×640 budget counts on")
    }

    @Test("LAY-EQ-01b: 1000×720 fits both cards open; 880×640 fits every preset with Tone folded")
    func railBudget() {
        let full = Self.railBudget(windowHeight: 720)
        let small = Self.railBudget(windowHeight: NowPlayingLayout.windowMinHeight)
        #expect(full == 556 && small == 476)
        let open = EQLayout.toneCardHeight(rows: Self.toneRows)
        let folded = EQLayout.toneCardHeight(rows: 0)
        #expect(Self.equalizerCardHeight + Self.cardGap + open <= full,
                "1000×720: both cards, Tone open — \(Self.equalizerCardHeight + Self.cardGap + open) of \(full)")
        #expect(Self.equalizerCardHeight + Self.cardGap + folded <= small,
                "880×640: Tone folded — \(Self.equalizerCardHeight + Self.cardGap + folded) of \(small)")
    }

    @Test("LAY-EQ-01c: each Tone slider keeps a usable width beside the name and value columns")
    func sliderWidth() {
        let columns = EQLayout.toneNameWidth + EQLayout.toneValueWidth
        let gaps = 4 * EQLayout.toneRowGap // the row's inset at each end, and between its three parts
        let slider = Self.railWidth - 2 * EQLayout.toneCardPadding - gaps - columns
        // 48 half-decibel steps across ±12 dB: at least ~1.7 pt per step for the pointer.
        #expect(slider >= 80, "the slider is \(slider) pt")
    }
}
