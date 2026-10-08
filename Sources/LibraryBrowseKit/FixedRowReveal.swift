// MARK: - FixedRowReveal (S10.8 E1 — scroll a row into view without the lazy stack's id lookup)

/// Where a list of fixed-height rows must scroll so one row is fully in view, moving as little as
/// possible — the `scrollTo` "no anchor" rule, done with arithmetic. A lazy stack scrolling to a row
/// by ID builds every row up to it (and keeps them): End over 10,000 songs built them all, and every
/// later key rebuilt them all (the S10.8 End-key hang). With a fixed row height the row's place is
/// known without building anything.
///
/// The rows sit between equal top and bottom `inset`s, with no gaps. The revealed span is the row
/// plus one inset each side, so the first and last rows come into view with the list's margin.
public enum FixedRowReveal {
    /// The content offset (the visible top) that brings row `index` into view: its top at the top
    /// when it is above the visible span, its bottom at the bottom when it is below (its top, if the
    /// span is too short to hold it); nil when it is already fully in view.
    public static func offset(revealing index: Int, rowHeight: Double, inset: Double,
                              visibleTop: Double, visibleHeight: Double) -> Double? {
        let top = Double(index) * rowHeight // the row's top, less its inset
        let bottom = top + rowHeight + 2 * inset // the row's bottom, plus its inset
        if top < visibleTop {
            return top
        }
        if bottom > visibleTop + visibleHeight {
            return min(top, bottom - visibleHeight)
        }
        return nil
    }
}
