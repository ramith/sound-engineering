import LibraryBrowseKit
import Testing

// MARK: - FacetAlbumGrouping (S9.6 — album-section runs from album-ordered tracks)

@Suite("FacetAlbumGrouping — consecutive album runs")
struct FacetAlbumGroupingTests {
    /// A minimal stub — the grouping is generic over `AlbumGroupable`, so no `LibraryTrackDisplay`.
    private struct Row: AlbumGroupable, Identifiable, Equatable {
        let id: Int
        let albumID: Int64?
        let albumName: String?
        let year: Int?
    }

    @Test("consecutive same-album tracks form one section; a change starts a new one, order kept")
    func runs() {
        let rows = [
            Row(id: 1, albumID: 10, albumName: "A", year: 2001),
            Row(id: 2, albumID: 10, albumName: "A", year: 2001),
            Row(id: 3, albumID: 20, albumName: "B", year: 2005),
        ]
        let sections = FacetAlbumGrouping.sections(from: rows)
        #expect(sections.map(\.id) == [10, 20])
        #expect(sections[0].tracks.map(\.id) == [1, 2])
        #expect(sections[1].tracks.map(\.id) == [3])
        #expect(sections[0].title == "A")
        #expect(sections[0].year == "2001")
    }

    @Test("a nil album groups under 'Unknown Album' with id -1")
    func nilAlbum() {
        let sections = FacetAlbumGrouping.sections(
            from: [Row(id: 1, albumID: nil, albumName: nil, year: nil)]
        )
        #expect(sections.count == 1)
        #expect(sections[0].id == -1)
        #expect(sections[0].title == "Unknown Album")
        #expect(sections[0].year == nil)
    }

    @Test("a non-positive year yields a nil section year (never a bare '0')")
    func zeroYear() {
        let sections = FacetAlbumGrouping.sections(
            from: [Row(id: 1, albumID: 5, albumName: "X", year: 0)]
        )
        #expect(sections[0].year == nil)
    }

    @Test("empty input → no sections")
    func empty() {
        #expect(FacetAlbumGrouping.sections(from: [Row]()).isEmpty)
    }
}
