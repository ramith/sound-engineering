// MARK: - DetailListMetrics (S10.8 E — the fixed heights a detail page's list is built from)

/// The heights of a detail page's list lines — all fixed, so the list places a row by arithmetic
/// (`DetailTrackLayout.span(ofRow:metrics:)`) instead of asking the lazy stack to find it.
public struct DetailListMetrics: Sendable, Equatable {
    /// From one row's top to the next (the page's one row pitch).
    public let rowHeight: Double
    /// An artist page's album header.
    public let albumHeaderHeight: Double
    /// A "Disc 2" sub-header in an album with more than one disc.
    public let discHeaderHeight: Double

    public init(rowHeight: Double, albumHeaderHeight: Double, discHeaderHeight: Double) {
        self.rowHeight = rowHeight
        self.albumHeaderHeight = albumHeaderHeight
        self.discHeaderHeight = discHeaderHeight
    }
}
