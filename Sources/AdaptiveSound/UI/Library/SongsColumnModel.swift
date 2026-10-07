import Foundation
import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Songs column behaviour (the app half of `SongColumn`)

/// The column CATALOG (identity, labels, fixed layout) is pure data in `LibraryBrowseKit` so the
/// header-fit test can measure it. This extension adds what needs the store's row type and the
/// app's formatters: the header-click comparator and the row-cell display string.
extension SongColumn {
    /// The sort comparator for a header click, or `nil` for display-only columns (index, genre,
    /// and the new technical columns that `SongSortMapping` doesn't map). Same keypaths the old
    /// Table used, so the DAO mapping is unchanged.
    func comparator(_ order: SortOrder) -> KeyPathComparator<LibraryTrackDisplay>? {
        // Function-local (not `static`): a `KeyPathComparator` holds a non-Sendable `PartialKeyPath`,
        // so a stored table trips Swift 6 concurrency (the `SongSortMapping` idiom); rebuilding this
        // small map on the rare header render/click is negligible. Same keypaths the old Table used,
        // so `SongSortMapping` + the DAO mapping are unchanged. Display-only columns are absent → nil.
        let comparators: [SongColumn: KeyPathComparator<LibraryTrackDisplay>] = [
            .title: KeyPathComparator(\.title, order: order),
            .artist: KeyPathComparator(\.artistName, order: order),
            .album: KeyPathComparator(\.albumName, order: order),
            .year: KeyPathComparator(\.year, order: order),
            .duration: KeyPathComparator(\.durationMs, order: order),
            .dateAdded: KeyPathComparator(\.dateAdded, order: order),
            .quality: KeyPathComparator(\.format, order: order), // Quality + Format both sort by container
            .format: KeyPathComparator(\.format, order: order),
            .trackNo: KeyPathComparator(\.trackNo, order: order),
            .discNo: KeyPathComparator(\.discNo, order: order),
            .fileSize: KeyPathComparator(\.fileSize, order: order),
            .playCount: KeyPathComparator(\.playCount, order: order),
            .albumArtist: KeyPathComparator(\.albumArtistName, order: order),
        ]
        let comparator = comparators[self]
        // The Kit's `isSortable` is what the header-fit test budgets the sort arrow from; keep it
        // honest against this table (the behaviour) rather than trusting two lists to stay equal.
        assert((comparator != nil) == isSortable,
               "SongColumn.\(rawValue): isSortable (LibraryBrowseKit) disagrees with the comparator table")
        return comparator
    }

    /// The row-cell display string for this column ("" → blank cell). A STATIC formatter table
    /// (built once): each closure captures nothing, so it's `Sendable` — unlike `comparator`'s
    /// keypath-bearing values. Index / Title render specially in the row, so they're absent here.
    func displayText(_ track: LibraryTrackDisplay) -> String {
        Self.formatters[self]?(track) ?? ""
    }

    private static let formatters: [SongColumn: @Sendable (LibraryTrackDisplay) -> String] = [
        .artist: { $0.artistDisplayName },
        .album: { $0.albumName ?? "" },
        .genre: { $0.genreName ?? "" },
        .albumArtist: { $0.albumArtistDisplayName },
        .format: { $0.format },
        .quality: { qualityString(format: $0.format, sampleRate: $0.sampleRate, bitDepth: $0.bitDepth) },
        .year: { $0.year.flatMap { $0 > 0 ? String($0) : nil } ?? "" },
        .duration: { $0.durationSeconds > 0 ? formatDuration($0.durationSeconds) : "" },
        .dateAdded: { compactDate($0.dateAdded) },
        .sampleRate: { track in
            guard let rate = track.sampleRate, rate > 0 else { return "" }
            return (Double(rate) / 1000).formatted(.number.precision(.fractionLength(0 ... 1))) + " kHz"
        },
        .bitDepth: { $0.bitDepth.flatMap { $0 > 0 ? "\($0)-bit" : nil } ?? "" },
        .trackNo: { $0.trackNo.flatMap { $0 > 0 ? String($0) : nil } ?? "" },
        .discNo: { $0.discNo.flatMap { $0 > 0 ? String($0) : nil } ?? "" },
        .fileSize: { $0.fileSize > 0 ? $0.fileSize.formatted(.byteCount(style: .file)) : "" },
        .playCount: { $0.playCount > 0 ? $0.playCount.formatted(.number) : "" },
        .lastPlayed: { $0.lastPlayed.map { compactDate($0) } ?? "" },
    ]
}
