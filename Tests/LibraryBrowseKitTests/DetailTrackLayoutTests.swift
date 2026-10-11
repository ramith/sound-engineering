import LibraryBrowseKit
import Testing

// MARK: - DetailTrackLayout (S10.8 E2/E3 — a detail page's song list, as shown)

/// PLAY-01: on an album, artist or genre page, a row's double-click, Return or Play plays the PAGE in
/// the order shown, from that row on (decision 11). PLAY-02: an artist page's queue is its shown order.
@Suite("DetailTrackLayout — the shown order, the numbers, and what a row plays")
struct DetailTrackLayoutTests {
    /// A minimal song: the layout is generic over `DetailTrack`, so no `LibraryTrackDisplay` fixture.
    /// (Its optionals default to nil in the memberwise init.)
    private struct Song: DetailTrack, Equatable {
        let id: Int64
        var albumID: Int64?
        var albumName: String?
        var year: Int?
        var trackNo: Int?
    }

    /// An album's read: disc / track order, one song untagged (no track number).
    private let album = [
        Song(id: 11, albumID: 1, albumName: "Roja", year: 1992, trackNo: 1),
        Song(id: 12, albumID: 1, albumName: "Roja", year: 1992, trackNo: 2),
        Song(id: 13, albumID: 1, albumName: "Roja", year: 1992, trackNo: nil),
        Song(id: 14, albumID: 1, albumName: "Roja", year: 1992, trackNo: 4),
    ]

    /// An artist's read, as the store orders it (album id, NULL first; then disc / track): a song with
    /// no album, then two albums — one song in "Rockstar" with no track number.
    private let artist = [
        Song(id: 41),
        Song(id: 21, albumID: 4, albumName: "Bombay", year: 1995, trackNo: 3),
        Song(id: 22, albumID: 4, albumName: "Bombay", year: 1995, trackNo: 4),
        Song(id: 31, albumID: 9, albumName: "Rockstar", year: 2011, trackNo: 7),
        Song(id: 32, albumID: 9, albumName: "Rockstar", year: 2011, trackNo: nil),
    ]

    /// What the list draws, as text: "h<album id> <title> <year>" for an album header, "<id>#<number>"
    /// for a song ("-": none).
    private func drawn(_ layout: DetailTrackLayout<Song>) -> [String] {
        layout.items.map { item in
            switch item {
            case let .header(albumID, title, year): "h\(albumID) \(title) \(year ?? "-")"
            case let .row(song, number): "\(song.id)#\(number.map(String.init) ?? "-")"
            }
        }
    }

    /// The songs the list draws, top to bottom.
    private func drawnSongs(_ layout: DetailTrackLayout<Song>) -> [Int64] {
        layout.items.compactMap { item in
            if case let .row(song, _) = item {
                return song.id
            }
            return nil
        }
    }

    // MARK: Album (E2)

    @Test("an album shows its read order, each song led by its track number — its place when untagged")
    func albumOrderAndNumbers() {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        #expect(layout.rows.map(\.id) == [11, 12, 13, 14])
        #expect(drawn(layout) == ["11#1", "12#2", "13#3", "14#4"])
    }

    @Test("PLAY-01 album: a row plays the whole album from that row on", arguments: [
        (Int64(11), 0), (Int64(13), 2), (Int64(14), 3),
    ])
    func albumPlaysFromRow(id: Int64, start: Int) throws {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        let request = try #require(layout.playFromRow(id))
        #expect(request.tracks.map(\.id) == [11, 12, 13, 14])
        #expect(request.startIndex == start)
        #expect(request.tracks[request.startIndex].id == id)
    }

    @Test("PLAY-01 a row not on the page plays nothing")
    func foreignRowPlaysNothing() {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        #expect(layout.playFromRow(99) == nil)
        #expect(layout.index(of: 99) == nil)
    }

    @Test("an empty page has no rows and plays nothing")
    func emptyPage() {
        let layout = DetailTrackLayout(tracks: [Song](), arrangement: .byAlbum)
        #expect(layout.rows.isEmpty)
        #expect(layout.items.isEmpty)
        #expect(layout.playFromRow(11) == nil)
    }

    @Test("the selection survives the page reloading under it, by id (SEL-08 on a page)")
    func selectionSurvivesReload() {
        var selection = ListSelection<Int64>()
        let before = DetailTrackLayout(tracks: album, arrangement: .album)
        selection.click(12, extend: false, toggle: false, in: before.rows.map(\.id))
        selection.click(13, extend: true, toggle: false, in: before.rows.map(\.id))
        // A rescan: a song joins at the top, one that was not selected leaves.
        let reloaded = DetailTrackLayout(
            tracks: [Song(id: 10, albumID: 1, trackNo: 0)] + album.filter { $0.id != 14 }, arrangement: .album
        )
        let rows = reloaded.rows.map(\.id)
        #expect(selection.ids == [12, 13])
        #expect(selection.keyboardCursor(in: rows)?.id == 13)
        selection.move(.step(1), extend: true, in: rows) // ⇧↓ from the same anchor, in the new rows
        #expect(selection.ids == [12, 13]) // 13 is now last: nothing below it
        selection.move(.step(-1), extend: true, in: rows)
        #expect(selection.ids == [12])
    }

    // MARK: Artist (E3)

    @Test("an artist's songs sit under one header per album, each numbered within its album")
    func artistGroupsByAlbum() {
        let layout = DetailTrackLayout(tracks: artist, arrangement: .byAlbum)
        #expect(drawn(layout) == [
            "h-1 Unknown Album -", "41#1",
            "h4 Bombay 1995", "21#3", "22#4",
            "h9 Rockstar 2011", "31#7", "32#2", // untagged: its place in its album
        ])
        #expect(layout.rows.map(\.id) == [41, 21, 22, 31, 32])
    }

    @Test("PLAY-01 artist: a row plays the artist's songs, album by album, from that row on", arguments: [
        (Int64(41), 0), (Int64(22), 2), (Int64(32), 4),
    ])
    func artistPlaysFromRow(id: Int64, start: Int) throws {
        let layout = DetailTrackLayout(tracks: artist, arrangement: .byAlbum)
        let request = try #require(layout.playFromRow(id))
        #expect(request.tracks.map(\.id) == [41, 21, 22, 31, 32])
        #expect(request.startIndex == start)
    }

    @Test("PLAY-02 the artist queue is the SHOWN order — even for a song read apart from its album")
    func artistQueueIsShownOrder() throws {
        // A read that interleaves two albums: the page shows each album once, its songs together.
        let read = [artist[1], artist[3], artist[2], artist[4]] // 21 (Bombay), 31 (Rockstar), 22, 32
        let layout = DetailTrackLayout(tracks: read, arrangement: .byAlbum)
        #expect(drawn(layout) == ["h4 Bombay 1995", "21#3", "22#4", "h9 Rockstar 2011", "31#7", "32#2"])
        let shown = drawnSongs(layout)
        #expect(layout.rows.map(\.id) == shown)
        for (position, id) in shown.enumerated() {
            let request = try #require(layout.playFromRow(id))
            #expect(request.tracks.map(\.id) == shown) // the queue, top to bottom, is what is shown
            #expect(request.startIndex == position)
        }
    }

    // MARK: Genre (E3)

    @Test("a genre is one flat list in its read order, with no numbers")
    func genreIsFlat() {
        let read = [artist[3], artist[1], artist[0]]
        let layout = DetailTrackLayout(tracks: read, arrangement: .flat)
        #expect(drawn(layout) == ["31#-", "21#-", "41#-"])
    }

    @Test("PLAY-01 genre: a row plays the genre's songs from that row on", arguments: [
        (Int64(31), 0), (Int64(21), 1), (Int64(41), 2),
    ])
    func genrePlaysFromRow(id: Int64, start: Int) throws {
        let layout = DetailTrackLayout(tracks: [artist[3], artist[1], artist[0]], arrangement: .flat)
        let request = try #require(layout.playFromRow(id))
        #expect(request.tracks.map(\.id) == [31, 21, 41])
        #expect(request.startIndex == start)
    }

    // MARK: Scrolling a row into view

    @Test("a row's span: every row and header a fixed height; an album's first song brings its header")
    func spans() {
        let grouped = DetailTrackLayout(tracks: artist, arrangement: .byAlbum)
        // The stack: h 0–44, 41 44–92, h 92–136, 21 136–184, 22 184–232, h 232–276, 31 276–324, 32 324–372.
        let spans = (0 ..< 5).map { grouped.span(ofRow: $0, rowHeight: 48, headerHeight: 44) }
        #expect(spans.map(\.top) == [0, 92, 184, 232, 324])
        #expect(spans.map(\.height) == [92, 92, 48, 92, 48])
        let flat = DetailTrackLayout(tracks: album, arrangement: .album).span(ofRow: 3, rowHeight: 48, headerHeight: 44)
        #expect(flat.top == 144)
        #expect(flat.height == 48)
    }
}
