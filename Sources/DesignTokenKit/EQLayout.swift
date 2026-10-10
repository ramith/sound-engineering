// EQLayout — the EQ screen's layout data (Sprint EQ, UI plan §5.6; the `NowPlayingLayout`
// precedent), in the Kit so LAY-EQ-01 asserts the rail's height budget headlessly instead of
// trusting prose. The views lay out from these values and the test derives from the same ones.
//
// EQ3t lands the Tone card's part: its rows, columns and the two heights it can have. macOS 26
// ignores Dynamic Type, so the card holds by structure (fixed rows, a fixed name column, one-line
// labels) and its height is exact.

import Foundation

public enum EQLayout {
    // MARK: - The Tone card (EQ3t)

    /// A Tone row — the name over its range, the slider, the value — at the plan's 29 pt.
    public static let toneRowHeight: Double = 29
    /// The fixed name column, so the five sliders line up (and hold at large text, §5.6).
    public static let toneNameWidth: Double = 68
    /// The value column: wide enough for "+12.0" in the micro mono face.
    public static let toneValueWidth: Double = 32
    /// Between a row's name, slider and value, and inside its tint at each end.
    public static let toneRowGap: Double = 6
    /// The header row: the fold chip ("TONE"), Reset Tone.
    public static let toneHeaderHeight: Double = 18
    /// Between the header and the first row, while open.
    public static let toneHeaderGap: Double = 2
    /// The card's padding, on every side.
    public static let toneCardPadding: Double = 10

    /// The Tone card's height with `rows` rows showing: folded (0), its header alone — the plan's
    /// one line; open (the five regions), the header and every row.
    public static func toneCardHeight(rows: Int) -> Double {
        let body = rows > 0 ? toneHeaderGap + Double(rows) * toneRowHeight : 0
        return 2 * toneCardPadding + toneHeaderHeight + body
    }
}
