// EQScreenLayout — the EQ screen's V1b layout data (Sprint EQ, EQ3; ui-plan §5.6), in the Kit like
// `NowPlayingLayout`, so LAY-EQ-01 asserts the height budget headlessly instead of trusting prose. The
// app lays the screen out from these same values: the rail's rows, headers and paddings are framed to
// them, so the arithmetic is the layout's, not an estimate of it.
//
// The screen, both rail cards — the Equalizer card and the Tone card (EQ3t) — and the graph card live
// here: one layout source. macOS 26 ignores Dynamic Type, so the cards hold by structure (fixed rows,
// fixed columns, one-line labels) and their heights are exact.

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
    /// Each rail card's inner padding (the Equalizer card's and the Tone card's).
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

    // MARK: The Tone card (EQ3t; under the Equalizer card)

    /// A Tone row — the name over its range, the slider, the value — at the plan's 29 pt.
    public static let toneRowHeight: Double = 29
    /// The fixed name column, so the five sliders line up (and hold at large text, §5.6).
    public static let toneNameWidth: Double = 68
    /// The value column: wide enough for "+12.0" in the micro mono face (the unit is the slider's).
    public static let toneValueWidth: Double = 32
    /// Between a row's name, slider and value, and inside its tint at each end.
    public static let toneRowGap: Double = 6
    /// The header row: the fold chip ("TONE"), Reset Tone.
    public static let toneHeaderHeight: Double = 18
    /// Between the header and the first row, while open.
    public static let toneHeaderGap: Double = 2

    /// The Tone card's height with `rows` rows showing: folded (0), its header alone — the plan's one
    /// line; open (the five regions), the header and every row.
    public static func toneCardHeight(rows: Int) -> Double {
        let body = rows > 0 ? toneHeaderGap + Double(rows) * toneRowHeight : 0
        return 2 * railCardPadding + toneHeaderHeight + body
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
