// MARK: - FillGridLayout (S10.8 D5 — the browse grid's fill-width columns)

/// The browse grid's columns (Albums, Artists, Genres): as many tiles at least `minimumTile` wide as
/// fit across `width` with `spacing` between them — never fewer than `minimumColumns` — and the tile
/// width that fills `width` exactly, so no gutter is left over and the right edge is never ragged.
/// With the grid's values (160-pt tiles, 12-pt gaps, inside 12-pt side insets) the count is
/// `max(2, ⌊(W − 24 + 12) / 172⌋)` for a grid area `W` wide. Pure, so the layout and the arrow keys'
/// row length come from one tested rule.
public struct FillGridLayout: Equatable, Sendable {
    /// Tiles per row.
    public let columns: Int
    /// Each tile's width; zero for an unmeasured or nonsense `width`.
    public let tileWidth: Double

    /// - Parameter width: the width the tiles and the gaps between them share (the grid area less
    ///   its side insets).
    public init(width: Double, minimumTile: Double, spacing: Double, minimumColumns: Int) {
        let fit = GridLayoutMath.columnsThatFit(width: width, minimum: minimumTile, spacing: spacing)
        columns = max(minimumColumns, fit)
        let tile = (width - spacing * Double(columns - 1)) / Double(columns)
        tileWidth = tile.isFinite ? max(0, tile) : 0
    }
}
