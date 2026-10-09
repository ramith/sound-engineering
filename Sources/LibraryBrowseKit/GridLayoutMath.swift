// MARK: - GridLayoutMath (S10.8 decision 20 — the grid arithmetic the keys need)

/// The browse grid's layout arithmetic for the keyboard: how many tiles a row holds and how far a
/// page moves. Pure, so the keys and the layout cannot disagree untested.
public enum GridLayoutMath {
    /// As many `minimum`-wide tiles as fit in `width` points with `spacing` between them, at least
    /// one — the count `FillGridLayout` builds on. The browse grid lays out exactly that many
    /// FLEXIBLE columns (S10.8 D5), so this is the row length the arrow keys step by by
    /// construction. (The rule is also SwiftUI's own for an adaptive `GridItem`, checked offscreen
    /// at 457 widths when the grid used one.) Capped at 1 000 — a sanity bound, never a real layout.
    public static func columnsThatFit(width: Double, minimum: Double, spacing: Double) -> Int {
        let fit = ((width + spacing) / (minimum + spacing)).rounded(.down)
        return fit >= 1 ? Int(min(fit, 1000)) : 1 // NaN / negative / zero → one column
    }

    /// The rows a Page Up / Down moves: the whole rows a viewport of `viewportHeight` shows at a row
    /// pitch (tile plus gap) of `rowPitch`, at least one.
    public static func rowsPerPage(viewportHeight: Double, rowPitch: Double) -> Int {
        let rows = (viewportHeight / rowPitch).rounded(.down)
        return rowPitch > 0 && rows >= 1 ? Int(min(rows, 1000)) : 1
    }

    /// The row pitch of laid-out tiles from their top edges — the smallest gap between two
    /// different tops (tiles in one row share a top). Nil until two rows are laid out.
    public static func rowPitch(tops: some Sequence<Double>) -> Double? {
        let sorted = Set(tops.map { ($0 * 2).rounded() / 2 }).sorted() // half-point grid: no float noise
        return zip(sorted, sorted.dropFirst()).map { $1 - $0 }.min()
    }
}
