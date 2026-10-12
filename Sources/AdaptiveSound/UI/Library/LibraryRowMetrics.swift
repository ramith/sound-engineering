import CoreGraphics
import LibraryBrowseKit

// MARK: - Library row metrics (S10.8 E — the measures Songs' rows and the pages' rows share)

/// The measures every Library song row is laid out on — Songs' rows and headers, and the album,
/// artist and genre pages' rows and section headers — so a number, a title and a time sit on the
/// same lines everywhere. (The row's height is `LibraryRowSize`.)
enum LibraryRowMetrics {
    /// From a row card's edge to its content, at each end.
    static let horizontalPadding: CGFloat = 12
    /// Between two columns of a row (and of Songs' column headers).
    static let columnSpacing: CGFloat = 14
    /// The leading number column: Songs' # column, so a page's track numbers sit where Songs' row
    /// numbers do.
    static let numberColumnWidth: CGFloat = SongColumn.index.width ?? 34
}
