// SettingsLayout — the Settings tab's card column (S10.8 F2): pure data, so the views and the
// layout / slot tests (LAY-SET-01, SLOT-07) share one set of numbers, as `EQScreenLayout` does for
// the EQ screen.

/// The Settings tab: one glass card per section (Output Device, Pure Mode), stacked in one column,
/// at most the readable width and centred in the tab, on the Twin Panels insets — the Library's and
/// the EQ's, so a card's top edge stays put across a tab switch. The column scrolls when the window is
/// too short for it.
///
/// Pure Mode's card ends in the signal-path status rows: a fixed label column ("Active path",
/// "Format", "Decoder", "EQ Preset") beside the values, which take the rest of the card's width and
/// wrap rather than truncate.
public enum SettingsLayout {
    // MARK: The column

    /// The column's widest: the app's readable width, defined here — `DesignSystem.LayoutMetrics
    /// .readableMaxWidth` forwards it, so the error banner caps at the same 720.
    public static let columnMaxWidth: Double = 720
    /// The content inset from the content region's top, sides and bottom (the Twin Panels insets).
    public static let insetTop = EQScreenLayout.insetTop
    public static let insetHorizontal = EQScreenLayout.insetHorizontal
    public static let insetBottom = EQScreenLayout.insetBottom
    /// The gap between two cards (the Twin Panels' gap between the cards).
    public static let cardGap = EQScreenLayout.columnGap
    /// Each card's inner padding — content stays clear of the panel's 22 pt corners.
    public static let cardPadding: Double = 20
    /// The gap between a card's rows: its title row, the device rows, a switch row, the status rows.
    public static let rowGap: Double = 12
    /// The title row's least height: the device pill's, so every card's title sits at one height.
    public static let titleRowMinHeight = DevicePillMetrics.minHeight
    /// The least gap between a card's title and the control trailing it (Output Device's device pill).
    public static let titleAccessoryGap: Double = 24

    /// A card's width in a window `windowWidth` wide: the readable width, or the window less its
    /// insets where that is narrower.
    public static func cardWidth(windowWidth: Double) -> Double {
        min(columnMaxWidth, windowWidth - 2 * insetHorizontal)
    }

    // MARK: The status rows (Pure Mode's signal path)

    /// The label column: a fixed slot its widest label must fit (SLOT-07).
    public static let statusLabelWidth: Double = 110
    /// The gap between the label column and the values.
    public static let statusColumnGap: Double = 8

    /// The value column's width in a window `windowWidth` wide: the card's, less its padding, the label
    /// column and the gap.
    public static func statusValueWidth(windowWidth: Double) -> Double {
        cardWidth(windowWidth: windowWidth) - 2 * cardPadding - statusLabelWidth - statusColumnGap
    }
}
