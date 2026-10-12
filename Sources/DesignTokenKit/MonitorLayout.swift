// MonitorLayout — the Monitoring tab's layout data (S10.8 G1): pure data, so the views and LAY-MON-01
// share one set of numbers, as `EQScreenLayout` does for the EQ screen and `SettingsLayout` for Settings.

/// The Monitoring tab: the header (title, caption, the Before / After legend) over one analyzer lens per
/// channel, on the Twin Panels insets — the Library's, the EQ's and Settings' — so the content's top edge
/// stays put across a tab switch. The lenses share the height under the header: with few channels they
/// divide it; once a share would drop under `rowMinHeight`, each lens keeps that height and the tab
/// scrolls (five channels fit at 1000×720, four at the 880×640 minimum — LAY-MON-01).
///
/// Inside a lens: the channel's name in a fixed column on the leading edge, then two equal halves split
/// by a hairline — BEFORE's bars on the left, AFTER's on the right — each under its own tag, so position
/// and label tell them apart without colour.
public enum MonitorLayout {
    // MARK: The screen

    /// The content inset from the content region's top, sides and bottom (the Twin Panels insets).
    public static let insetTop = EQScreenLayout.insetTop
    public static let insetHorizontal = EQScreenLayout.insetHorizontal
    public static let insetBottom = EQScreenLayout.insetBottom
    /// The header: the title over its caption, the legend beside them.
    public static let headerHeight: Double = 44
    /// The gap between the header and the first lens.
    public static let headerGap: Double = 12
    /// The gap between two lenses.
    public static let rowGap: Double = 12
    /// A lens's least height: a 42 pt bar field under the tag line. 88, not 96: with the lenses at their
    /// least, part of the next one still shows at the bottom of the tab (18 pt at 1000×720, 38 pt at
    /// 880×640), where 96 would leave the scrolled-off lens almost or fully out of sight.
    public static let rowMinHeight: Double = 88

    /// The height the lenses share in a content region `regionHeight` tall (the window less the chrome
    /// and footer bands): the region less the insets, the header and its gap — 500 pt at 1000×720,
    /// 420 pt at the 880×640 minimum.
    public static func rowsHeight(regionHeight: Double) -> Double {
        regionHeight - insetTop - headerHeight - headerGap - insetBottom
    }

    /// Each lens's height with `channelCount` channels in a content region `regionHeight` tall: an equal
    /// share of `rowsHeight` less the gaps between the lenses, never under `rowMinHeight`.
    public static func rowHeight(channelCount: Int, regionHeight: Double) -> Double {
        guard channelCount > 0 else { return rowMinHeight }
        let gaps = Double(channelCount - 1) * rowGap
        return max(rowMinHeight, (rowsHeight(regionHeight: regionHeight) - gaps) / Double(channelCount))
    }

    // MARK: Inside a lens

    /// The lens's inner padding, every side: clear of its 20 pt corners, and the bars' foot this far
    /// above the lens's bottom edge, inside the dark bleed's band (R4-MON-01b audits them there).
    public static let lensPadding: Double = 12
    /// The leading column holding the channel's name ("L", "LFE", "Rss", "Ch 7").
    public static let labelColumnWidth: Double = 44
    /// The tag line: the channel's name and the BEFORE / AFTER tags, each centred in it.
    public static let tagLineHeight: Double = 16
    /// Between a half's tag and its bars.
    public static let tagGap: Double = 6
    /// Between each half's content and the hairline that splits them.
    public static let halfGap: Double = 12
}
