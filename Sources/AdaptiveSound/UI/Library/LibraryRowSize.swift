import CoreGraphics

// MARK: - Library row size (S10.8 E — Songs' 48 pt rows, the pages' 36 pt single-line rows)

/// How tall a Library song row is (`LibraryRowChrome`), and so how far apart its list's rows sit —
/// fixed, because the lists scroll a row into view by arithmetic on it (`FixedRowReveal`).
enum LibraryRowSize {
    /// Songs' rows, and a page's two-line rows (a genre's "Artist · Album" line): a 48 pt card, no gap.
    case regular
    /// A page's single-line rows (an album's, an artist's): the queue and playlist rows' 34 pt card
    /// and 2 pt seam — the 36 pt pitch (decision 5).
    case compact

    /// The row card's height.
    var cardHeight: CGFloat {
        switch self {
        case .regular: 48
        case .compact: DesignSystem.QueueRow.cardMinHeight
        }
    }

    /// The gap between two rows' cards (half above and half below each row).
    var seam: CGFloat {
        switch self {
        case .regular: 0
        case .compact: DesignSystem.QueueRow.cardSeam
        }
    }

    /// From one row's top to the next: the list's pitch, which sizes a Page Up / Down and places a
    /// row for scrolling.
    var pitch: CGFloat {
        cardHeight + seam
    }

    /// The card's corner radius (fill, now-playing edge and keyboard ring share it): Songs' own; the
    /// queue and playlist rows' for the compact card.
    var cornerRadius: CGFloat {
        switch self {
        case .regular: 11
        case .compact: DesignSystem.Radius.container
        }
    }
}
