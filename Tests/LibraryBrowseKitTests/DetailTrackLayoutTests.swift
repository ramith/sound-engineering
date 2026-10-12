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
        var title = ""
        var albumID: Int64?
        var albumName: String?
        var year: Int?
        var discNo: Int?
        var trackNo: Int?
    }

    /// An album as the store reads it — an untagged song FIRST (SQLite sorts a NULL track first).
    private let album = [
        Song(id: 13, title: "Untagged", albumID: 1, albumName: "Roja", year: 1992),
        Song(id: 11, title: "Chinna Chinna Aasai", albumID: 1, albumName: "Roja", year: 1992, trackNo: 1),
        Song(id: 12, title: "Kadhal Rojave", albumID: 1, albumName: "Roja", year: 1992, trackNo: 2),
        Song(id: 14, title: "Roja Jaaneman", albumID: 1, albumName: "Roja", year: 1992, trackNo: 4),
    ]

    /// An artist's read, as the store orders it (album id, NULL first): two loose songs with no album
    /// (carrying other albums' track numbers), then two albums — "Rockstar" with one untagged song.
    private let artist = [
        Song(id: 42, title: "Zariya", trackNo: 9),
        Song(id: 41, title: "Aao Balma", trackNo: 2),
        Song(id: 21, title: "Kannalanae", albumID: 4, albumName: "Bombay", year: 1995, trackNo: 3),
        Song(id: 22, title: "Hamma Hamma", albumID: 4, albumName: "Bombay", year: 1995, trackNo: 4),
        Song(id: 32, title: "Sadda Haq", albumID: 9, albumName: "Rockstar", year: 2011),
        Song(id: 31, title: "Kun Faya Kun", albumID: 9, albumName: "Rockstar", year: 2011, trackNo: 7),
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

    @Test("an album shows its songs by track number; a song without one comes last, its number blank")
    func albumOrderAndNumbers() {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        #expect(drawn(layout) == ["11#1", "12#2", "14#4", "13#-"])
        #expect(layout.rows.map(\.id) == [11, 12, 14, 13])
    }

    @Test("an album with NO track numbers is in title order, numbered by place")
    func untaggedAlbumNumbersByPlace() {
        let read = [Song(id: 1, title: "Zebra", albumID: 7), Song(id: 2, title: "alpha", albumID: 7),
                    Song(id: 3, title: "Mango", albumID: 7)]
        #expect(drawn(DetailTrackLayout(tracks: read, arrangement: .album)) == ["2#1", "3#2", "1#3"])
    }

    @Test("a multi-disc album goes disc by disc, track by track; ties and title order follow")
    func discThenTrackThenTitle() {
        let read = [
            Song(id: 1, title: "Beta", albumID: 7, discNo: 2, trackNo: 1),
            Song(id: 2, title: "No Disc Tag", albumID: 7, trackNo: 2), // a track with no disc: disc 1
            Song(id: 3, title: "Zulu", albumID: 7, discNo: 1, trackNo: 1),
            Song(id: 4, title: "Alpha", albumID: 7, discNo: 1, trackNo: 1), // a tie: by title
            Song(id: 5, title: "Disc Two Extra", albumID: 7, discNo: 2), // no track: ends its disc
            Song(id: 6, title: "Hidden", albumID: 7), // neither: ends the album
            Song(id: 7, title: "Track 10", albumID: 7, discNo: 2, trackNo: 10),
            Song(id: 8, title: "Track 9", albumID: 7, discNo: 2, trackNo: 9),
        ]
        let layout = DetailTrackLayout(tracks: read, arrangement: .album)
        #expect(drawn(layout) == ["4#1", "3#1", "2#2", "1#1", "8#9", "7#10", "5#-", "6#-"])
    }

    @Test("PLAY-01 album: a row plays the whole album, as shown, from that row on", arguments: [
        (Int64(11), 0), (Int64(14), 2), (Int64(13), 3),
    ])
    func albumPlaysFromRow(id: Int64, start: Int) throws {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        let request = try #require(layout.playFromRow(id))
        #expect(request.tracks.map(\.id) == [11, 12, 14, 13])
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
        let before = DetailTrackLayout(tracks: album, arrangement: .album) // 11, 12, 14, 13
        selection.click(12, extend: false, toggle: false, in: before.rows.map(\.id))
        selection.click(14, extend: true, toggle: false, in: before.rows.map(\.id))
        // A rescan: a new first track joins, and one that was not selected leaves.
        let rescanned = [Song(id: 10, title: "Intro", albumID: 1, trackNo: 0)] + album.filter { $0.id != 13 }
        let rows = DetailTrackLayout(tracks: rescanned, arrangement: .album).rows.map(\.id) // 10, 11, 12, 14
        #expect(selection.ids == [12, 14])
        #expect(selection.keyboardCursor(in: rows)?.id == 14)
        selection.move(.step(1), extend: true, in: rows) // ⇧↓ from the same anchor, in the new rows
        #expect(selection.ids == [12, 14]) // 14 is now last: nothing below it
        selection.move(.step(-1), extend: true, in: rows)
        #expect(selection.ids == [12])
    }

    // MARK: Artist (E3)

    @Test("an artist's songs sit under one header per album, each album in its own track order")
    func artistGroupsByAlbum() {
        let layout = DetailTrackLayout(tracks: artist, arrangement: .byAlbum)
        #expect(drawn(layout) == [
            "h-1 Unknown Album -", "41#-", "42#-", // loose songs: by title, other albums' numbers not shown
            "h4 Bombay 1995", "21#3", "22#4",
            "h9 Rockstar 2011", "31#7", "32#-", // the untagged song after the numbered one, blank
        ])
        #expect(layout.rows.map(\.id) == [41, 42, 21, 22, 31, 32])
    }

    @Test("PLAY-01 artist: a row plays the artist's songs, album by album, from that row on", arguments: [
        (Int64(41), 0), (Int64(22), 3), (Int64(32), 5),
    ])
    func artistPlaysFromRow(id: Int64, start: Int) throws {
        let layout = DetailTrackLayout(tracks: artist, arrangement: .byAlbum)
        let request = try #require(layout.playFromRow(id))
        #expect(request.tracks.map(\.id) == [41, 42, 21, 22, 31, 32])
        #expect(request.startIndex == start)
    }

    @Test("PLAY-02 the artist queue is the SHOWN order — track order, not the title order it was read in")
    func artistQueueIsShownOrder() throws {
        // Read in TITLE order, the two albums interleaved: track order differs from it in both.
        let read = [
            Song(id: 51, title: "Aye Hairathe", albumID: 5, albumName: "Guru", year: 2007, trackNo: 5),
            Song(id: 61, title: "Chaiyya Chaiyya", albumID: 6, albumName: "Dil Se", year: 1998, trackNo: 1),
            Song(id: 62, title: "Dil Se Re", albumID: 6, albumName: "Dil Se", year: 1998, trackNo: 3),
            Song(id: 52, title: "Ek Lo Ek Muft", albumID: 5, albumName: "Guru", year: 2007, trackNo: 4),
            Song(id: 63, title: "Jiya Jale", albumID: 6, albumName: "Dil Se", year: 1998, trackNo: 2),
            Song(id: 53, title: "Tere Bina", albumID: 5, albumName: "Guru", year: 2007, trackNo: 2),
        ]
        let layout = DetailTrackLayout(tracks: read, arrangement: .byAlbum)
        #expect(drawn(layout) == [
            "h5 Guru 2007", "53#2", "52#4", "51#5",
            "h6 Dil Se 1998", "61#1", "63#2", "62#3",
        ])
        let shown = drawnSongs(layout)
        #expect(shown != read.map(\.id)) // the page's order is not the read's
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
        let read = [artist[5], artist[2], artist[0]]
        let layout = DetailTrackLayout(tracks: read, arrangement: .flat)
        #expect(drawn(layout) == ["31#-", "21#-", "42#-"])
    }

    @Test("PLAY-01 genre: a row plays the genre's songs from that row on", arguments: [
        (Int64(31), 0), (Int64(21), 1), (Int64(42), 2),
    ])
    func genrePlaysFromRow(id: Int64, start: Int) throws {
        let layout = DetailTrackLayout(tracks: [artist[5], artist[2], artist[0]], arrangement: .flat)
        let request = try #require(layout.playFromRow(id))
        #expect(request.tracks.map(\.id) == [31, 21, 42])
        #expect(request.startIndex == start)
    }

    // MARK: Scrolling a row into view

    @Test("a row's span at the 36 pt pitch: fixed rows and headers; an album's first song brings its header")
    func spansAtCompactPitch() {
        let grouped = DetailTrackLayout(tracks: artist, arrangement: .byAlbum)
        // The stack: h 0–44, 41 44–80, 42 80–116, h 116–160, 21 160–196, 22 196–232, h 232–276,
        // 31 276–312, 32 312–348.
        let spans = (0 ..< 6).map { grouped.span(ofRow: $0, rowHeight: 36, headerHeight: 44) }
        #expect(spans.map(\.top) == [0, 80, 116, 196, 232, 312])
        #expect(spans.map(\.height) == [80, 36, 80, 36, 80, 36])
        // An album page has no headers: row 3 of 36 pt rows.
        let albumRow = DetailTrackLayout(tracks: album, arrangement: .album)
            .span(ofRow: 3, rowHeight: 36, headerHeight: 44)
        #expect(albumRow.top == 108)
        #expect(albumRow.height == 36)
    }

    @Test("a row's span at the 48 pt pitch (a genre's two-line rows): no headers, the row alone")
    func spansAtRegularPitch() {
        let flat = DetailTrackLayout(tracks: artist, arrangement: .flat)
        let spans = (0 ..< 6).map { flat.span(ofRow: $0, rowHeight: 48, headerHeight: 44) }
        #expect(spans.map(\.top) == [0, 48, 96, 144, 192, 240])
        #expect(spans.allSatisfy { $0.height == 48 })
    }
}
