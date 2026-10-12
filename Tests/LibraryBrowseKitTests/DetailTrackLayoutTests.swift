import LibraryBrowseKit
import Testing

// MARK: - DetailTrackLayout (S10.8 E2/E3 — a detail page's song list, as shown)

/// PLAY-01: on an album, artist or genre page, a row's double-click, Return or Play plays the PAGE in
/// the order shown, from that row on (decision 11). PLAY-02: an artist page's queue is its shown order.
/// (Placing a row — spans and paging — is `DetailTrackLayoutPlacementTests`.)
@Suite("DetailTrackLayout — the shown order, the numbers, and what a row plays")
struct DetailTrackLayoutTests {
    private typealias Song = DetailTestSong
    private let album = DetailTestSongs.album
    private let artist = DetailTestSongs.artist
    private let twoDiscs = DetailTestSongs.twoDiscs

    private func drawn(_ layout: DetailTrackLayout<Song>) -> [String] {
        DetailTestSongs.drawn(layout)
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

    @Test("a multi-disc album goes disc by disc under a header each, track by track; ties by title")
    func discThenTrackThenTitle() {
        let layout = DetailTrackLayout(tracks: twoDiscs, arrangement: .album)
        #expect(drawn(layout) == ["d1", "4#1", "3#1", "2#2", "d2", "1#1", "8#9", "7#10", "5#-", "d-", "6#-"])
        // Each row knows its disc, for VoiceOver's "Disc 2, Track 1".
        #expect(DetailTestSongs.drawnDiscs(layout) == ["4:1", "3:1", "2:1", "1:2", "8:2", "7:2", "5:2", "6:-"])
    }

    @Test("a one-disc album has no disc header and its rows carry no disc — even tagged 'disc 1'")
    func singleDiscHasNoCue() {
        let read = [Song(id: 1, title: "A", albumID: 7, discNo: 1, trackNo: 1),
                    Song(id: 2, title: "B", albumID: 7, trackNo: 2)]
        let layout = DetailTrackLayout(tracks: read, arrangement: .album)
        #expect(drawn(layout) == ["1#1", "2#2"])
        #expect(DetailTestSongs.drawnDiscs(layout) == ["1:-", "2:-"])
    }

    @Test("a track or disc number of zero or less is no number: it orders and shows as untagged")
    func nonPositiveNumbersAreUntagged() {
        let read = [
            Song(id: 1, title: "Zero Track", albumID: 7, trackNo: 0),
            Song(id: 2, title: "Negative Track", albumID: 7, trackNo: -3),
            Song(id: 3, title: "Second", albumID: 7, discNo: 0, trackNo: 2), // disc 0: disc 1, like no tag
            Song(id: 4, title: "First", albumID: 7, discNo: -1, trackNo: 1),
        ]
        let layout = DetailTrackLayout(tracks: read, arrangement: .album)
        #expect(drawn(layout) == ["4#1", "3#2", "2#-", "1#-"]) // no disc header: one real disc
        let allUntagged = DetailTrackLayout(tracks: [read[0], read[1]], arrangement: .album)
        #expect(drawn(allUntagged) == ["2#1", "1#2"]) // by title, numbered by place
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
        // A rescan: a new track 3 joins between them, and one that was not selected leaves.
        let rescanned = [Song(id: 10, title: "Interlude", albumID: 1, trackNo: 3)] + album.filter { $0.id != 13 }
        let rows = DetailTrackLayout(tracks: rescanned, arrangement: .album).rows.map(\.id) // 11, 12, 10, 14
        #expect(selection.ids == [12, 14])
        #expect(selection.keyboardCursor(in: rows)?.id == 14)
        selection.move(.step(1), extend: true, in: rows) // ⇧↓ from the same anchor, in the new rows
        #expect(selection.ids == [12, 14]) // 14 is last: nothing below it
        selection.move(.step(-1), extend: true, in: rows)
        #expect(selection.ids == [12, 10]) // the range from the kept anchor, over the new rows
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
        let shown = DetailTestSongs.drawnSongs(layout)
        #expect(shown != read.map(\.id)) // the page's order is not the read's
        #expect(layout.rows.map(\.id) == shown)
        for (position, id) in shown.enumerated() {
            let request = try #require(layout.playFromRow(id))
            #expect(request.tracks.map(\.id) == shown) // the queue, top to bottom, is what is shown
            #expect(request.startIndex == position)
        }
    }

    // MARK: Genre (E3)

    @Test("a genre is one flat list, album after album as read, with no numbers or headers")
    func genreIsFlat() {
        let read = [artist[5], artist[2], artist[0]]
        let layout = DetailTrackLayout(tracks: read, arrangement: .flat)
        #expect(drawn(layout) == ["31#-", "21#-", "42#-"])
    }

    @Test("a genre orders each album's run as that album's own pages do — disc, track, title")
    func genreOrdersEachAlbum() {
        // Both albums read out of track order; the two-disc album keeps its discs' order, unheaded.
        let read = [artist[4], artist[5]] + twoDiscs // Rockstar: untagged, then track 7
        let layout = DetailTrackLayout(tracks: read, arrangement: .flat)
        #expect(drawn(layout) == ["31#-", "32#-", "4#-", "3#-", "2#-", "1#-", "8#-", "7#-", "5#-", "6#-"])
        let albumPage = DetailTrackLayout(tracks: twoDiscs, arrangement: .album)
        #expect(Array(layout.rows.map(\.id).suffix(8)) == albumPage.rows.map(\.id)) // every page agrees
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

    // MARK: A tile's verbs (the page's order)

    @Test("a tile's order IS its page's rows, for every arrangement — never the read's", arguments: [
        DetailTrackArrangement.album, .byAlbum, .flat,
    ])
    func tileOrderIsPageOrder(arrangement: DetailTrackArrangement) {
        let read = twoDiscs + artist
        let page = DetailTrackLayout(tracks: read, arrangement: arrangement)
        #expect(DetailTrackLayout.pageOrder(read, arrangement: arrangement).map(\.id) == page.rows.map(\.id))
        #expect(page.rows.map(\.id) != read.map(\.id)) // the page re-orders this read
    }
}
