// MARK: - GridLayoutMath (S10.8 decision 20 — the grid arithmetic the keys need)

/// The browse grid's layout arithmetic for the keyboard: how many tiles a row holds and how far a
/// page moves. Pure, so the keys and the layout cannot disagree untested.
public enum GridLayoutMath {
    /// Columns of an adaptive `GridItem(.adaptive(minimum:), spacing:)` in `width` points — as many
    /// `minimum`-wide tiles as fit with `spacing` between them, at least one. This is the count
    /// SwiftUI lays out: checked offscreen against a real `LazyVGrid` at 457 widths, the fractional
    /// widths around every column boundary included. (Capped at 1 000 — a sanity bound, never a
    /// real layout.)
    public static func adaptiveColumns(width: Double, minimum: Double, spacing: Double) -> Int {
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
