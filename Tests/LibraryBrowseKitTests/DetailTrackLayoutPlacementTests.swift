import LibraryBrowseKit
import Testing

// MARK: - DetailTrackLayout placement (S10.8 E — scroll a row into view, Page Up / Down)

/// A detail page places its rows by arithmetic on fixed heights (`DetailListMetrics`): a row's span
/// for scrolling it into view, and how many rows a Page key moves.
@Suite("DetailTrackLayout — a row's span, and a page of rows")
struct DetailTrackLayoutPlacementTests {
    private typealias Song = DetailTestSong
    private let album = DetailTestSongs.album
    private let artist = DetailTestSongs.artist
    private let twoDiscs = DetailTestSongs.twoDiscs
    private let metrics = DetailTestSongs.metrics

    // MARK: Scrolling a row into view

    @Test("a row's span at the 36 pt pitch: fixed rows and headers; an album's first song brings its header")
    func spansAtCompactPitch() {
        let grouped = DetailTrackLayout(tracks: artist, arrangement: .byAlbum)
        // The stack: h 0–44, 41 44–80, 42 80–116, h 116–160, 21 160–196, 22 196–232, h 232–276,
        // 31 276–312, 32 312–348.
        let spans = (0 ..< 6).map { grouped.span(ofRow: $0, metrics: metrics) }
        #expect(spans.map(\.top) == [0, 80, 116, 196, 232, 312])
        #expect(spans.map(\.height) == [80, 36, 80, 36, 80, 36])
        // An album page has no headers: row 3 of 36 pt rows.
        let albumRow = DetailTrackLayout(tracks: album, arrangement: .album).span(ofRow: 3, metrics: metrics)
        #expect(albumRow.top == 108)
        #expect(albumRow.height == 36)
    }

    @Test("a row's span at the 48 pt pitch (a genre's two-line rows): no headers, the row alone")
    func spansAtRegularPitch() {
        let flat = DetailTrackLayout(tracks: artist, arrangement: .flat)
        let regular = DetailListMetrics(rowHeight: 48, albumHeaderHeight: 44, discHeaderHeight: 28)
        let spans = (0 ..< 6).map { flat.span(ofRow: $0, metrics: regular) }
        #expect(spans.map(\.top) == [0, 48, 96, 144, 192, 240])
        #expect(spans.allSatisfy { $0.height == 48 })
    }

    @Test("a disc's first song brings its disc header; an album's first song, both headers")
    func spansWithDiscHeaders() {
        // An artist page of the two-disc album: h 0–44, d1 44–72, 4 72–108, 3 108–144, 2 144–180,
        // d2 180–208, 1 208–244, 8 244–280, 7 280–316, 5 316–352, d- 352–380, 6 380–416.
        let layout = DetailTrackLayout(tracks: twoDiscs, arrangement: .byAlbum)
        let spans = layout.rows.indices.map { layout.span(ofRow: $0, metrics: metrics) }
        #expect(spans.map(\.top) == [0, 108, 144, 180, 244, 280, 316, 352])
        #expect(spans.map(\.height) == [108, 36, 36, 64, 36, 36, 36, 64])
    }

    // MARK: Page Up / Page Down

    @Test("a page is what fits in the viewport less the row left behind — headers take their share")
    func pageRowsWalkSpans() {
        let layout = DetailTrackLayout(tracks: twoDiscs, arrangement: .byAlbum) // rows 4 3 2 | 1 8 7 5 | 6
        // 150 pt less the 36 pt row left behind = 114 pt of travel.
        // Down from row 0: 36 + 36 (rows 1, 2) = 72; row 3 with its disc header (64) would make 136.
        #expect(layout.pageRows(from: 0, direction: 1, viewportHeight: 150, metrics: metrics) == 2)
        // Down from row 3 (plain rows after it): 36 × 3 = 108 fits; a fourth (the "d-" row, 64) does not.
        #expect(layout.pageRows(from: 3, direction: 1, viewportHeight: 150, metrics: metrics) == 3)
        // Up from row 4: row 4 is plain (36), row 3 leads its disc (64) = 100; row 2 (36) would make 136.
        #expect(layout.pageRows(from: 4, direction: -1, viewportHeight: 150, metrics: metrics) == 2)
        // A flat page of the same pitch pages by plain rows: 114 / 36 = 3.
        let flat = DetailTrackLayout(tracks: twoDiscs, arrangement: .flat)
        #expect(flat.pageRows(from: 0, direction: 1, viewportHeight: 150, metrics: metrics) == 3)
    }

    @Test("a page moves at least one row, and no more than there are")
    func pageRowsEdges() {
        let layout = DetailTrackLayout(tracks: twoDiscs, arrangement: .byAlbum)
        #expect(layout.pageRows(from: 0, direction: 1, viewportHeight: 10, metrics: metrics) == 1) // tiny view
        #expect(layout.pageRows(from: 7, direction: 1, viewportHeight: 400, metrics: metrics) == 1) // at the end
        #expect(layout.pageRows(from: 0, direction: -1, viewportHeight: 400, metrics: metrics) == 1) // at the top
        #expect(layout.pageRows(from: 0, direction: 1, viewportHeight: 4000, metrics: metrics) == 7) // all below
        let empty = DetailTrackLayout(tracks: [Song](), arrangement: .album)
        #expect(empty.pageRows(from: 0, direction: 1, viewportHeight: 400, metrics: metrics) == 1)
    }
}
