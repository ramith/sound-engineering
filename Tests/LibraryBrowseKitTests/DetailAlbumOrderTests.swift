import LibraryBrowseKit
import Testing

// MARK: - Album order, years and disc folders (S10.8 E break-it 1, 2, 3, 5, 6)

@Suite("DetailTrackLayout — album order, album years, disc folders")
struct DetailAlbumOrderTests {
    private typealias Song = DetailTestSong

    private func drawn(_ layout: DetailTrackLayout<Song>) -> [String] {
        DetailTestSongs.drawn(layout)
    }

    /// A song in disc folder `disc` of "/Music/Live Set" — no disc tag, as a per-disc rip has.
    private func ripped(_ id: Int64, _ title: String, disc: Int, track: Int, folder: String = "/Music/Live Set")
        -> Song {
        Song(id: id, title: title, albumID: 7, trackNo: track, discFolder: DiscFolder(disc: disc, albumFolder: folder))
    }

    // MARK: Disc folders (break-it 1)

    @Test("a set ripped one folder per disc, with no disc tags, plays disc by disc under its disc headers")
    func discFoldersPlayDiscByDisc() {
        let read = [
            ripped(1, "Overture", disc: 1, track: 1), ripped(4, "Another Start", disc: 2, track: 1),
            ripped(2, "Zebra Crossing", disc: 1, track: 2), ripped(5, "Yesterday Again", disc: 2, track: 2),
        ]
        let layout = DetailTrackLayout(tracks: read, arrangement: .album)
        #expect(drawn(layout) == ["d1", "1#1", "2#2", "d2", "4#1", "5#2"])
        #expect(DetailTestSongs.drawnDiscs(layout) == ["1:1", "2:1", "4:2", "5:2"])
    }

    @Test("disc folders count only as siblings in one album folder, naming two discs or more")
    func discFoldersMustBeSiblings() {
        // Two folders named "CD 1" under DIFFERENT album folders: not one set — by track, then title.
        let apart = [ripped(1, "B", disc: 1, track: 1, folder: "/Music/X"),
                     ripped(2, "A", disc: 2, track: 1, folder: "/Music/Y")]
        #expect(drawn(DetailTrackLayout(tracks: apart, arrangement: .album)) == ["2#1", "1#1"])
        // One disc folder alone: a one-disc album, no headers.
        let alone = [ripped(1, "B", disc: 1, track: 2), ripped(2, "A", disc: 1, track: 1)]
        #expect(drawn(DetailTrackLayout(tracks: alone, arrangement: .album)) == ["2#1", "1#2"])
    }

    @Test("a disc tag wins over the folder; the folder fills in only for the untagged songs")
    func discTagWinsOverFolder() {
        let read = [
            ripped(1, "Tagged Two", disc: 1, track: 1), // in "CD 1" but tagged disc 2
            ripped(2, "Folder One", disc: 1, track: 1),
            ripped(3, "Folder Two", disc: 2, track: 2),
        ]
        let tagged = [Song(id: 1, title: "Tagged Two", albumID: 7, discNo: 2, trackNo: 1,
                           discFolder: read[0].discFolder), read[1], read[2]]
        let layout = DetailTrackLayout(tracks: tagged, arrangement: .album)
        #expect(drawn(layout) == ["d1", "2#1", "d2", "1#1", "3#2"])
    }

    // MARK: Album years (break-it 2, 3)

    @Test("an album header shows the ALBUM's year — not the year of whichever song is read first")
    func headerShowsTheAlbumYear() {
        let read = [
            Song(id: 1, title: "Bonus", albumID: 4, albumName: "Bombay", albumYear: 1995), // no song year
            Song(id: 2, title: "Old One", albumID: 5, albumName: "Hits", year: 1974, albumYear: 1992),
        ]
        let layout = DetailTrackLayout(tracks: read, arrangement: .byAlbum)
        #expect(drawn(layout) == ["h5 Hits 1992", "2#-", "h4 Bombay 1995", "1#-"])
    }

    @Test("without the album's year, the year most of its songs share — the earliest of a tie")
    func headerFallsBackToTheCommonSongYear() {
        let read = [Song(id: 1, title: "A", albumID: 4, albumName: "X", year: 2001),
                    Song(id: 2, title: "B", albumID: 4, albumName: "X", year: 1999),
                    Song(id: 3, title: "C", albumID: 4, albumName: "X", year: 1999),
                    Song(id: 4, title: "D", albumID: 6, albumName: "Y", year: 2005),
                    Song(id: 5, title: "E", albumID: 6, albumName: "Y", year: 2003)]
        let years = FacetAlbumGrouping.sections(from: read).map(\.year)
        #expect(years == ["1999", "2003"])
    }

    @Test("the songs with no album show no year, whatever theirs are")
    func looseSongsHaveNoYear() {
        let read = [Song(id: 1, title: "Single", year: 2001), Song(id: 2, title: "Other", year: 2001)]
        #expect(drawn(DetailTrackLayout(tracks: read, arrangement: .byAlbum)) == ["h-1 Unknown Album -", "2#-", "1#-"])
    }

    // MARK: Album order (break-it 5)

    @Test("albums go by year, then title, then id — undated after dated, loose songs last — in any read order")
    func albumOrderIsStable() {
        let songs = [
            Song(id: 1, title: "z", albumID: 30, albumName: "Zulu", albumYear: 2010),
            Song(id: 2, title: "a", albumID: 20, albumName: "alpha", albumYear: 2010), // same year: by title
            Song(id: 3, title: "u", albumID: 10, albumName: "Undated"),
            Song(id: 4, title: "o", albumID: 40, albumName: "Oldest", albumYear: 1990),
            Song(id: 5, title: "l", year: 1950), // no album: last, whatever its year
            Song(id: 6, title: "t", albumID: 50, albumName: "alpha", albumYear: 2010), // a same-titled album: by id
        ]
        let expected = ["h40 Oldest 1990", "4#-", "h20 alpha 2010", "2#-", "h50 alpha 2010", "6#-",
                        "h30 Zulu 2010", "1#-", "h10 Undated -", "3#-", "h-1 Unknown Album -", "5#-"]
        #expect(drawn(DetailTrackLayout(tracks: songs, arrangement: .byAlbum)) == expected)
        #expect(drawn(DetailTrackLayout(tracks: songs.reversed(), arrangement: .byAlbum)) == expected)
        let flat = DetailTrackLayout(tracks: songs.reversed(), arrangement: .flat).rows.map(\.id)
        #expect(flat == [4, 2, 6, 1, 3, 5]) // a genre lists its albums in the same order
    }

    // MARK: Numbers on an artist's page (break-it 6)

    @Test("an artist's page never makes a number up: its songs of an album may be the untagged ones")
    func artistPageNeverNumbersByPlace() {
        let guest = [Song(id: 1, title: "Guest Song", albumID: 5, albumName: "Hits"),
                     Song(id: 2, title: "Another Guest", albumID: 5, albumName: "Hits")]
        #expect(drawn(DetailTrackLayout(tracks: guest, arrangement: .byAlbum)) == ["h5 Hits -", "2#-", "1#-"])
        // The album's own page, holding the whole (untagged) album, numbers by place.
        #expect(drawn(DetailTrackLayout(tracks: guest, arrangement: .album)) == ["2#1", "1#2"])
    }
}
