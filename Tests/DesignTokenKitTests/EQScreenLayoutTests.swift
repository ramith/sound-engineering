// LAY-EQ-01 — the EQ screen's layout budget (ui-plan §5.6): the rail's two cards — the Equalizer card
// (EQ3) and the Tone card (EQ3t) — and the graph's plot. Every number comes from `EQScreenLayout`, which
// the views are framed to.

import DesignTokenKit
import Testing

@Suite("EQ layout — the screen's budget (LAY-EQ-01)")
struct EQScreenLayoutTests {
    /// The design's rail: the 7 built-ins and 2 My Presets.
    private static let designRows = 7 + 2
    /// The Tone card's five regions (decision 24).
    private static let toneRows = 5

    /// The Tone card open (its five rows) and folded (its one line).
    private static let toneOpen = EQScreenLayout.toneCardHeight(rows: toneRows)
    private static let toneFolded = EQScreenLayout.toneCardHeight(rows: 0)

    private static let fullHeight = 720.0
    private static let minimumHeight = NowPlayingLayout.windowMinHeight

    /// The rail with the Equalizer card at `rows` and the Tone card at `tone`.
    private static func rail(rows: Int, tone: Double) -> Double {
        EQScreenLayout.equalizerCardHeight(rows: rows) + EQScreenLayout.railCardGap + tone
    }

    @Test("LAY-EQ-01a: the Tone card is one line folded, and five 29 pt rows more open")
    func toneCardHeights() {
        #expect(Self.toneFolded == 2 * EQScreenLayout.railCardPadding + EQScreenLayout.toneHeaderHeight)
        #expect(Self.toneOpen
            == Self.toneFolded + EQScreenLayout.toneHeaderGap + Double(Self.toneRows) * EQScreenLayout.toneRowHeight)
        #expect(EQScreenLayout.toneRowHeight == 29, "the plan's row height")
        #expect(Self.toneFolded <= 40, "folded, the card is the one line the 880×640 budget counts on")
    }

    @Test("LAY-EQ-01b: each Tone slider keeps a usable width beside the name and value columns")
    func toneSliderWidth() {
        let columns = EQScreenLayout.toneNameWidth + EQScreenLayout.toneValueWidth
        let gaps = 4 * EQScreenLayout.toneRowGap // the row's inset at each end, and between its three parts
        let slider = EQScreenLayout.railWidth - 2 * EQScreenLayout.railCardPadding - gaps - columns
        // 48 half-decibel steps across ±12 dB: at least ~1.7 pt per step for the pointer.
        #expect(slider >= 80, "the slider is \(slider) pt")
    }

    @Test("LAY-EQ-01d: the columns have 556 pt at 1000×720 and 476 pt at the 880×640 minimum")
    func contentHeight() {
        #expect(EQScreenLayout.contentHeight(windowHeight: Self.fullHeight) == 556)
        #expect(EQScreenLayout.contentHeight(windowHeight: Self.minimumHeight) == 476)
    }

    @Test("LAY-EQ-01e: 1000×720 fits both cards with Tone open; 880×640 fits every preset with Tone folded")
    func railFits() {
        let full = EQScreenLayout.contentHeight(windowHeight: Self.fullHeight)
        let small = EQScreenLayout.contentHeight(windowHeight: Self.minimumHeight)
        let open = Self.rail(rows: Self.designRows, tone: Self.toneOpen)
        let folded = Self.rail(rows: Self.designRows, tone: Self.toneFolded)
        #expect(open <= full, "1000×720, Tone open: \(open) of \(full)")
        #expect(folded <= small, "880×640, Tone folded: \(folded) of \(small)")
        #expect(EQScreenLayout.presetRowHeight == 28, "the plan's row height")
    }

    /// At 880×640 with Tone open the Equalizer card scrolls inside itself; the Tone card stays whole.
    /// The card still shows its title, the first header and a useful run of presets.
    @Test("LAY-EQ-01f: at 880×640 with Tone open the Equalizer card scrolls, with ≥ 5 preset rows in view")
    func scrollingCardKeepsRows() {
        let small = EQScreenLayout.contentHeight(windowHeight: Self.minimumHeight)
        let card = small - EQScreenLayout.railCardGap - Self.toneOpen
        #expect(card < EQScreenLayout.equalizerCardHeight(rows: Self.designRows), "it scrolls")
        let list = card - 2 * EQScreenLayout.railCardPadding - EQScreenLayout.titleRowHeight
        let rows = (list - EQScreenLayout.sectionHeaderHeight) / EQScreenLayout.presetRowHeight
        #expect(rows >= 5, "\(rows) preset rows in view")
    }

    @Test("LAY-EQ-01g: the plot is ≥ 280 pt tall at 880×640, and each band's column ≥ 16 pt wide")
    func plot() {
        let height = EQScreenLayout.plotHeight(windowHeight: Self.minimumHeight)
        #expect(height >= 280, "the plot is \(height) pt tall at the minimum window")
        #expect(EQScreenLayout.plotHeight(windowHeight: Self.fullHeight) == height + 80)
        // 31 bands across the plot: 30 gaps. Each band's column is its hit area.
        let pitch = EQScreenLayout.plotWidth(windowWidth: NowPlayingLayout.windowMinWidth) / 30
        #expect(pitch >= 16, "a band's column is \(pitch) pt wide at the minimum window")
    }
}
