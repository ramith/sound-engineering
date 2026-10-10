// EQScreenLayout — the EQ screen's V1b layout data (Sprint EQ, EQ3; ui-plan §5.6), in the Kit like
// `NowPlayingLayout`, so LAY-EQ-01 asserts the height budget headlessly instead of trusting prose. The
// app lays the screen out from these same values: the rail's rows, headers and paddings are framed to
// them, so the arithmetic is the layout's, not an estimate of it.
//
// The screen, the Equalizer card and the graph card live here; the Tone card's own metrics are
// EQ3t's `EQLayout` (built in parallel — a separate type so the two land without a file conflict).

import Foundation

public enum EQScreenLayout {
    // MARK: The screen (the Library's Twin Panels insets)

    /// Content inset from the content region's top, sides and bottom, and the gap between the columns.
    public static let insetTop: Double = 22
    public static let insetHorizontal: Double = 22
    public static let insetBottom: Double = 18
    public static let columnGap: Double = 20

    /// The height the two columns share in a window `windowHeight` tall: the window less the chrome and
    /// footer bands and the insets — 556 pt at 1000×720, 476 pt at the 880×640 minimum.
    public static func contentHeight(windowHeight: Double) -> Double {
        windowHeight - NowPlayingLayout.chromeHeight - NowPlayingLayout.footerHeight - insetTop - insetBottom
    }

    // MARK: The rail (the Equalizer card, then the Tone card)

    /// The rail's width: the Library rail's (`DesignSystem.LayoutMetrics.sidebarIdeal` forwards it).
    public static let railWidth: Double = 234
    /// The gap between the Equalizer card and the Tone card below it.
    public static let railCardGap: Double = 12
    /// The Equalizer card's inner padding.
    public static let railCardPadding: Double = 10
    /// The "Equalizer" title and its On/Off switch.
    public static let titleRowHeight: Double = 30
    /// A section header ("Presets", "My Presets").
    public static let sectionHeaderHeight: Double = 26
    /// One preset row — denser than the Library rail's 38 pt, so both cards fit at 1000×720.
    public static let presetRowHeight: Double = 28

    /// The Equalizer card's natural height with `rows` preset rows (built-ins and My Presets, or the
    /// "none yet" line): what it hugs before it scrolls.
    public static func equalizerCardHeight(rows: Int) -> Double {
        2 * railCardPadding + titleRowHeight + 2 * sectionHeaderHeight + Double(rows) * presetRowHeight
    }

    // MARK: The graph card

    /// The graph card's inner padding.
    public static let graphCardPadding: Double = 16
    /// The header's height at the default text size: the name and its chip, with room for EQ4's
    /// "Used on" line under them, beside the pills.
    public static let headerHeight: Double = 44
    /// The gap between the header and the graph's lens.
    public static let headerGap: Double = 12
    /// The plot's insets inside the lens: the strip and region names above, the frequency axis below,
    /// the dB labels leading.
    public static let plotInsetTop: Double = 52
    public static let plotInsetBottom: Double = 34
    public static let plotInsetLeading: Double = 44
    public static let plotInsetTrailing: Double = 22

    /// The plot's height in a window `windowHeight` tall (the header on one row).
    public static func plotHeight(windowHeight: Double) -> Double {
        contentHeight(windowHeight: windowHeight) - 2 * graphCardPadding - headerHeight - headerGap
            - plotInsetTop - plotInsetBottom
    }

    /// The plot's width in a window `windowWidth` wide: the window less the insets, the rail and the gap,
    /// the card's padding and the plot's side insets.
    public static func plotWidth(windowWidth: Double) -> Double {
        windowWidth - 2 * insetHorizontal - railWidth - columnGap - 2 * graphCardPadding
            - plotInsetLeading - plotInsetTrailing
    }
}
