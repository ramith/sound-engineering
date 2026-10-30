import Foundation
import LibraryBrowseKit
import LibraryStore
import Testing

// MARK: - R1.1-B break-it, the one search rule (BI-P)

//
// Red tests written against the combined sprint branch (34ad6efe): the shipped `SearchRule`, the tabs'
// `FacetTextFilter`, the `SearchQueryGate` that Songs and ⌘F share, and the Songs search over a real store.

@Suite("R1.1-B break-it — the one search rule (BI-P)")
struct BreakItSearchTests {
    @Test("BI-P08: an emoji's variation selector is no word — “❤️” must not find “☀️ Summer”, in a tab or in Songs")
    func variationSelectorIsNoWord() async throws {
        // U+FE0F (VARIATION SELECTOR-16, a nonspacing mark) follows most emoji. The rule reads every mark
        // as a word character, so each emoji leaves a one-scalar "word" behind, and every emoji query
        // matches every emoji title.
        #expect(SearchRule.words(of: "☀️ Summer") == ["summer"],
                "“☀️ Summer” reads as words \(SearchRule.words(of: "☀️ Summer").map { $0.unicodeScalars.map(\.value) })")
        #expect(!SearchRule.Query("❤️").matches(["☀️ Summer"]), "the Albums Filter: “❤️” finds “☀️ Summer”")

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("bi-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
        let files = ["sun", "plain"].map {
            ScannedFile(url: base.appendingPathComponent("\($0).flac"), name: $0, format: "FLAC", fileSize: 1, mtime: 1)
        }
        let ids = try await store.upsert(files, folderID: nil, generation: store.beginScanGeneration())
        try await store.applyMetadata(TrackMetadata(title: "☀️ Summer"), forTrack: ids[0])
        try await store.applyMetadata(TrackMetadata(title: "Plain Song"), forTrack: ids[1])
        // Two characters: past the gate, as ⌘F and the Songs tab search it.
        let found = try await store.searchMatchingIDs("❤️❤️")
        #expect(found.isEmpty, "the Songs search: “❤️❤️” found \(found.sorted()) (“☀️ Summer”)")
    }

    @Test("BI-P09: one query, one answer — a one-letter Filter in Albums, Artists, Genres gates as Songs and ⌘F do")
    func oneLetterGatesInEveryTab() {
        // “b”: the Songs tab shows every song (below the gate its search is off), ⌘F shows nothing, and the
        // Albums, Artists and Genres Filters narrow to the items with a word starting with “b”.
        #expect(FacetTextFilter.isActive("b") == SearchQueryGate.shouldQuery("b"),
                "a one-letter query narrows the Albums / Artists / Genres tabs but not Songs or ⌘F")
        let albums = ["Blue", "Red"]
        let kept = FacetTextFilter.filter(albums, query: "b") { [$0] }
        #expect(kept == albums, "the Albums Filter kept \(kept) for “b”, while Songs keeps every song")
    }
}
