import Foundation
import LibraryStore

// MARK: - SongSortMapping (S9.5 — pure sort-column decision)

/// Pure mapping from the Songs `Table`'s active-column comparator to a `TrackSort` DAO order.
/// Extracted from `LibraryBrowseModel` so it is unit-testable — the app executable target can't be
/// `@testable`-imported, so the mapping lived untested inside it. `LibraryBrowseModel.applySortOrder`
/// now delegates here. This only PICKS which `TrackSort` applies; the actual ordering stays
/// index-driven in SQL (`allTracksDisplay(sortedBy:)`), never a client-side sort of the ≤20k set.
public enum SongSortMapping {
    /// The composite grouped default: used when there is no sort column, or the active column is not
    /// sortable (Genre/Artwork). Artist → Album → disc → track → id.
    public static let defaultSort: TrackSort = .artistAlbumTrack

    /// Translate the PRIMARY comparator (keypath + direction) into its `TrackSort`. An empty order or
    /// an unrecognized keypath falls back to `defaultSort`.
    ///
    /// The keypath→pair table is a function-local, not a stored `static let`: `PartialKeyPath` is not
    /// `Sendable`, so a non-isolated global of it trips Swift 6 concurrency checking. Rebuilding nine
    /// entries on a header click is negligible, and keeps this a pure, nonisolated helper (callable
    /// from tests and the `@MainActor` model alike). Genre/Artwork are display-only → absent → default.
    public static func trackSort(for comparators: [KeyPathComparator<LibraryTrackDisplay>]) -> TrackSort {
        let table: [PartialKeyPath<LibraryTrackDisplay>: (asc: TrackSort, desc: TrackSort)] = [
            \LibraryTrackDisplay.title: (.titleAsc, .titleDesc),
            \LibraryTrackDisplay.artistName: (.artistNameAsc, .artistNameDesc),
            \LibraryTrackDisplay.albumName: (.albumTitleAsc, .albumTitleDesc),
            \LibraryTrackDisplay.durationMs: (.durationAsc, .durationDesc),
            \LibraryTrackDisplay.dateAdded: (.dateAddedAsc, .dateAddedDescending),
            \LibraryTrackDisplay.format: (.formatAsc, .formatDesc),
            \LibraryTrackDisplay.year: (.yearAsc, .yearDesc),
            \LibraryTrackDisplay.discNo: (.discNoAsc, .discNoDesc),
            \LibraryTrackDisplay.fileSize: (.fileSizeAsc, .fileSizeDesc),
        ]
        guard let primary = comparators.first, let pair = table[primary.keyPath] else { return defaultSort }
        return primary.order == .forward ? pair.asc : pair.desc
    }
}
