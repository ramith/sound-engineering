// MARK: - Detail page load (S10.8 E review 14 — what a page read found)

/// What reading an album, artist or genre page found (`LibraryBrowseModel.detailContent`).
enum LibraryDetailLoad {
    /// The page, to show (unless it is what's already shown).
    case page(LibraryDetailContent)
    /// The album, artist or genre is no longer in the library: the page closes.
    case gone
    /// The read failed (or the store isn't ready): the page keeps what it shows.
    case failed
}
