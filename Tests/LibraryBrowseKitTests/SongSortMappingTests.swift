import Foundation
import LibraryBrowseKit
import LibraryStore
import Testing

// MARK: - SongSortMapping (S9.5 sortable columns — the keypath→TrackSort wiring)

@Suite("SongSortMapping — column comparator → TrackSort")
struct SongSortMappingTests {
    private func sort(_ comparator: KeyPathComparator<LibraryTrackDisplay>) -> TrackSort {
        SongSortMapping.trackSort(for: [comparator])
    }

    @Test("each sortable column maps ASCENDING to its TrackSort")
    func ascending() {
        #expect(sort(KeyPathComparator(\.title, order: .forward)) == .titleAsc)
        #expect(sort(KeyPathComparator(\.artistName, order: .forward)) == .artistNameAsc)
        #expect(sort(KeyPathComparator(\.albumName, order: .forward)) == .albumTitleAsc)
        #expect(sort(KeyPathComparator(\.durationMs, order: .forward)) == .durationAsc)
        #expect(sort(KeyPathComparator(\.dateAdded, order: .forward)) == .dateAddedAsc)
        #expect(sort(KeyPathComparator(\.format, order: .forward)) == .formatAsc)
        #expect(sort(KeyPathComparator(\.year, order: .forward)) == .yearAsc)
        #expect(sort(KeyPathComparator(\.discNo, order: .forward)) == .discNoAsc)
        #expect(sort(KeyPathComparator(\.fileSize, order: .forward)) == .fileSizeAsc)
    }

    @Test("each sortable column maps DESCENDING to its TrackSort")
    func descending() {
        #expect(sort(KeyPathComparator(\.title, order: .reverse)) == .titleDesc)
        #expect(sort(KeyPathComparator(\.artistName, order: .reverse)) == .artistNameDesc)
        #expect(sort(KeyPathComparator(\.albumName, order: .reverse)) == .albumTitleDesc)
        #expect(sort(KeyPathComparator(\.durationMs, order: .reverse)) == .durationDesc)
        // Date Added's descending case is the pre-existing `.dateAddedDescending` (no `.dateAddedDesc`).
        #expect(sort(KeyPathComparator(\.dateAdded, order: .reverse)) == .dateAddedDescending)
        #expect(sort(KeyPathComparator(\.format, order: .reverse)) == .formatDesc)
        #expect(sort(KeyPathComparator(\.year, order: .reverse)) == .yearDesc)
        #expect(sort(KeyPathComparator(\.discNo, order: .reverse)) == .discNoDesc)
        #expect(sort(KeyPathComparator(\.fileSize, order: .reverse)) == .fileSizeDesc)
    }

    @Test("no sort column → composite grouped default")
    func emptyDefault() {
        #expect(SongSortMapping.trackSort(for: []) == .artistAlbumTrack)
        #expect(SongSortMapping.defaultSort == .artistAlbumTrack)
    }

    @Test("unrecognized (display-only) column → composite default")
    func unknownDefault() {
        // `id` and `trackNo` are not sortable columns (no TrackSort) → fallback, not a crash.
        #expect(sort(KeyPathComparator(\.id, order: .forward)) == .artistAlbumTrack)
        #expect(sort(KeyPathComparator(\.trackNo, order: .reverse)) == .artistAlbumTrack)
    }

    @Test("only the PRIMARY comparator drives the sort")
    func primaryOnly() {
        let comparators = [
            KeyPathComparator(\LibraryTrackDisplay.year, order: .reverse), // primary → yearDesc
            KeyPathComparator(\LibraryTrackDisplay.title, order: .forward), // secondary, ignored
        ]
        #expect(SongSortMapping.trackSort(for: comparators) == .yearDesc)
    }
}
