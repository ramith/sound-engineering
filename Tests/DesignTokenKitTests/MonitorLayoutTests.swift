// LAY-MON-01 — the Monitoring tab's lens column (S10.8 G1). Every number comes from `MonitorLayout`,
// which the views are framed to. AppKit measures the text here (the TEST target); the Kit stays UI-free.
// The strings are literals because the views that draw them live in the app target
// (`MonitoringTabView`'s header, `ChannelLabels`): if one changes, update it here too. NSFont metrics ≈
// (not ==) SwiftUI's, hence the 2 pt margin the other slot tests use.

import AppKit
import DesignTokenKit
import Testing

@Suite("Monitoring layout — the lens column (LAY-MON-01)")
struct MonitorLayoutTests {
    /// The two reference windows: the scene's default size and the hard minimum.
    private static let windows: [(width: Double, height: Double)] = [
        (1000, 720), (NowPlayingLayout.windowMinWidth, NowPlayingLayout.windowMinHeight),
    ]
    /// Mono, stereo, 5.1 and 7.1.
    private static let channelCounts = [1, 2, 6, 8]
    /// Large text (macOS max ≈ 1.4× default — the Kit's documented headroom factor).
    private static let largeText = NowPlayingLayout.maxTypeHeadroom
    /// The NSFont ↔ SwiftUI metric seam, as in `SlotFitTests`.
    private static let margin = 2.0

    /// The content region in a window `windowHeight` tall: what `MonitoringTabView` measures.
    private static func region(_ windowHeight: Double) -> Double {
        windowHeight - NowPlayingLayout.chromeHeight - NowPlayingLayout.footerHeight
    }

    /// The lens column's height with `count` lenses `row` tall.
    private static func stack(_ count: Int, row: Double) -> Double {
        Double(count) * row + Double(count - 1) * MonitorLayout.rowGap
    }

    private static func lineHeight(_ font: NSFont) -> Double {
        NSLayoutManager().defaultLineHeight(for: font)
    }

    @Test("LAY-MON-01a: the lenses share 500 pt at 1000×720 and 420 pt at the 880×640 minimum")
    func rowsHeight() {
        #expect(MonitorLayout.rowsHeight(regionHeight: Self.region(720)) == 500)
        #expect(MonitorLayout.rowsHeight(regionHeight: Self.region(NowPlayingLayout.windowMinHeight)) == 420)
        #expect(MonitorLayout.insetTop == EQScreenLayout.insetTop, "the content's top edge matches Library's and EQ's")
        #expect(MonitorLayout.insetHorizontal == SettingsLayout.insetHorizontal)
    }

    /// One and two channels divide the height exactly: the column fills it, nothing scrolls.
    @Test("LAY-MON-01b: 1 and 2 channels fill the height without scrolling, at both windows")
    func fewChannelsFill() {
        for window in Self.windows {
            let region = Self.region(window.height)
            let rows = MonitorLayout.rowsHeight(regionHeight: region)
            for count in [1, 2] {
                let row = MonitorLayout.rowHeight(channelCount: count, regionHeight: region)
                #expect(row > MonitorLayout.rowMinHeight, "\(count) ch at \(window): \(row) pt rows")
                #expect(abs(Self.stack(count, row: row) - rows) < 0.001, "\(count) ch at \(window) fills \(rows) pt")
            }
        }
    }

    /// Six and eight channels keep the least height and scroll; part of the first lens below the fold
    /// still shows, so the column reads as scrollable.
    @Test("LAY-MON-01c: 6 and 8 channels keep the least height and scroll, a lens peeking at the bottom")
    func manyChannelsScroll() {
        for window in Self.windows {
            let region = Self.region(window.height)
            let rows = MonitorLayout.rowsHeight(regionHeight: region)
            for count in [6, 8] {
                let row = MonitorLayout.rowHeight(channelCount: count, regionHeight: region)
                #expect(row == MonitorLayout.rowMinHeight, "\(count) ch at \(window): \(row) pt rows")
                #expect(Self.stack(count, row: row) > rows, "\(count) ch at \(window) scrolls")
            }
            // The view at rest: from the first lens's top to the region's bottom edge.
            let visible = region - MonitorLayout.insetTop - MonitorLayout.headerHeight - MonitorLayout.headerGap
            let pitch = MonitorLayout.rowMinHeight + MonitorLayout.rowGap
            let peek = visible.truncatingRemainder(dividingBy: pitch)
            #expect(peek >= 12 && peek < MonitorLayout.rowMinHeight, "at \(window), \(peek) pt of the next lens shows")
        }
    }

    /// Where the column turns from sharing to scrolling: five lenses fit at 1000×720, four at 880×640.
    @Test("LAY-MON-01d: the column scrolls from 6 channels at 1000×720 and from 5 at 880×640")
    func scrollThreshold() {
        let expected: [(window: Double, fits: Int)] = [(720, 5), (NowPlayingLayout.windowMinHeight, 4)]
        for (windowHeight, fits) in expected {
            let region = Self.region(windowHeight)
            let rows = MonitorLayout.rowsHeight(regionHeight: region)
            for count in Self.channelCounts + [fits, fits + 1] {
                let row = MonitorLayout.rowHeight(channelCount: count, regionHeight: region)
                let scrolls = Self.stack(count, row: row) > rows + 0.001
                #expect(scrolls == (count > fits), "\(count) ch at height \(windowHeight): scrolls = \(scrolls)")
            }
        }
    }

    /// The shortest lens keeps a readable bar field under its tag line, and the halves stay wide.
    @Test("LAY-MON-01e: the shortest lens has ≥ 40 pt of bars; each half ≥ 360 pt wide at 880 pt")
    func lensInterior() {
        let bars = MonitorLayout.rowMinHeight - 2 * MonitorLayout.lensPadding - MonitorLayout.tagLineHeight
            - MonitorLayout.tagGap
        #expect(bars >= 40, "the bar field is \(bars) pt")
        let lens = NowPlayingLayout.windowMinWidth - 2 * MonitorLayout.insetHorizontal
        let halves = lens - 2 * MonitorLayout.lensPadding - MonitorLayout.labelColumnWidth - 2 * MonitorLayout.halfGap
        // 44 bars a half: at least ~8 pt of pitch each.
        #expect(halves / 2 >= 360, "each half is \(halves / 2) pt wide")
    }

    /// The header as `MonitoringHeaderView` draws it: the title (`sectionTitle`, title3 semibold) over
    /// the caption (`caption`, callout), 4 pt apart — inside `headerHeight` at the default text size.
    @Test("LAY-MON-01f: the header's two lines fit its height")
    func headerFits() {
        let title = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold)
        let caption = NSFont.preferredFont(forTextStyle: .callout)
        let measured = Self.lineHeight(title) + 4 + Self.lineHeight(caption)
        #expect(measured <= MonitorLayout.headerHeight - Self.margin,
                "the header measures \(measured) pt against \(MonitorLayout.headerHeight)")
    }

    /// Every channel name `ChannelLabels` can draw (`bodyMedium`, body medium) fits the name column at
    /// large text, and the tag line holds it and the tags (`micro`, subheadline semibold).
    @Test("LAY-MON-01g: every channel name fits its column at large text; the tag line holds a line of each")
    func channelNamesFit() {
        let name = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .medium)
        let tag = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
                                    weight: .semibold)
        let names = ["M", "L", "R", "C", "LFE", "Ls", "Rs", "Lss", "Rss"] + (1 ... 8).map { "Ch \($0)" }
        for label in names {
            let width = NSAttributedString(string: label, attributes: [.font: name]).size().width * Self.largeText
            #expect(width <= MonitorLayout.labelColumnWidth - Self.margin,
                    "'\(label)' at large text measures \(width) pt against \(MonitorLayout.labelColumnWidth)")
        }
        #expect(Self.lineHeight(name) <= MonitorLayout.tagLineHeight, "the name's line fits the tag line")
        #expect(Self.lineHeight(tag) <= MonitorLayout.tagLineHeight, "a tag's line fits the tag line")
    }
}
