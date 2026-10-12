import Foundation
import LibraryBrowseKit
import LibraryStore
import Testing

// MARK: - Sprint E break-it (S10.8 E2/E3 — the detail pages over a real store)

/// Red tests from the Sprint E break-it pass (2026-10-12). Each builds a small library through the
/// store’s own write path, in a temporary folder, and lays a page out the way the app does
/// (`LibraryBrowseModel.detailContent`: the page’s read, then `DetailTrackLayout`) — so a fix in the
/// scan, the read or the kit turns it green. The findings and their severities are in `break-it-e.md`.
@Suite("Sprint E break-it — detail pages over a real store")
struct DetailPageBreakItTests {
    private typealias Page = DetailTrackLayout<LibraryTrackDisplay>

    /// A library in a temporary store. The store never opens a song’s file, so the paths are made up.
    private struct Library {
        let store: LibraryStore
        let folder: URL
        let root: Int64
        let generation: Int64

        static func make() async throws -> Library {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("sprint-e-break-it-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = try await LibraryStore(url: folder.appendingPathComponent("library.sqlite3"),
                                               appBuild: "break-it")
            let root = try await store.addRoot(URL(fileURLWithPath: "/BreakIt"))
            let generation = try await store.beginScanGeneration()
            return Library(store: store, folder: folder, root: root, generation: generation)
        }

        /// Adds the song at `path` (under the library’s one music folder) with its tags.
        func add(_ path: String, _ tags: TrackMetadata) async throws {
            let url = URL(fileURLWithPath: "/BreakIt/" + path)
            let name = url.deletingPathExtension().lastPathComponent
            let file = ScannedFile(url: url, relativePath: path, name: name, format: "FLAC", fileSize: 1000,
                                   mtime: 1000)
            for id in try await store.upsert([file], folderID: root, generation: generation) {
                try await store.applyMetadata(tags, forTrack: id)
            }
        }

        /// The end of a metadata pass: the albums regrouped, their years and covers shown.
        func settle() async throws {
            try await store.refreshDerivedFacets()
        }

        func discard() {
            try? FileManager.default.removeItem(at: folder)
        }

        /// An album’s page, as `detailContent(.album)` lays it out.
        func albumPage(_ title: String) async throws -> Page {
            let albums = try await store.albums()
            let album = try #require(albums.first { $0.title == title })
            return try await Page(tracks: store.tracksDisplay(inAlbum: album.id), arrangement: .album)
        }

        /// An artist’s page, as `detailContent(.artist)` lays it out.
        func artistPage(_ name: String) async throws -> Page {
            let artists = try await store.artists()
            let artist = try #require(artists.first { $0.name == name })
            return try await Page(tracks: store.tracksDisplay(byArtist: artist.id), arrangement: .byAlbum)
        }

        /// A genre’s page, as `detailContent(.genre)` lays it out.
        func genrePage(_ name: String) async throws -> Page {
            let genres = try await store.genres()
            let genre = try #require(genres.first { $0.name == name })
            return try await Page(tracks: store.tracksDisplay(inGenre: genre.id), arrangement: .flat)
        }
    }

    /// The page’s album headers: album id → the year shown ("-": none).
    private func headerYears(_ page: Page) -> [Int64: String] {
        var years: [Int64: String] = [:]
        for case let .header(albumID, _, year) in page.items {
            years[albumID] = year ?? "-"
        }
        return years
    }

    /// The number that leads `title`’s row on the page ("blank": none).
    private func numberShown(for title: String, on page: Page) -> String {
        for case let .row(track, number) in page.items where track.title == title {
            return number.map { String($0) } ?? "blank"
        }
        return "no such row"
    }

    /// A song of the album `album` by `artist`, credited to the same album artist.
    private func song(_ title: String, by artist: String = "Rahman", on album: String, year: Int? = nil,
                      disc: Int? = nil, track: Int? = nil) -> TrackMetadata {
        TrackMetadata(title: title, artistName: artist, albumTitle: album, albumArtistName: artist, year: year,
                      trackNo: track, discNo: disc, genres: ["Film"])
    }

    /// A song on the compilation “Hits” (flagged, credited to Various Artists).
    private func compilationSong(_ title: String, by artist: String, year: Int, track: Int?) -> TrackMetadata {
        TrackMetadata(title: title, artistName: artist, albumTitle: "Hits", albumArtistName: "Various Artists",
                      isCompilation: true, year: year, trackNo: track)
    }

    /// Rahman’s songs: the album “Bombay” (1995) with a bonus song that has no year and no number, one
    /// song (1974) on a compilation whose other songs are from 1992, and a single with no album (2001).
    private func addRahman(to library: Library) async throws {
        try await library.add("Bombay/bonus.flac", song("Bonus", on: "Bombay"))
        for track in 1 ... 3 {
            try await library.add("Bombay/\(track).flac", song("Song \(track)", on: "Bombay", year: 1995, track: track))
        }
        try await library.add("Hits/01.flac", compilationSong("Old One", by: "Rahman", year: 1974, track: 1))
        try await library.add("Hits/02.flac", compilationSong("New One", by: "Other", year: 1992, track: 2))
        try await library.add("Hits/03.flac", compilationSong("New Two", by: "Other", year: 1992, track: 3))
        try await library.add("s.flac", TrackMetadata(title: "Single", artistName: "Rahman", year: 2001, trackNo: 7))
        try await library.settle()
    }

    // MARK: Play order (PLAY-01 / PLAY-02)

    @Test("MAJOR — a set ripped one folder per disc, with no disc tags, plays disc by disc")
    func discFoldersPlayDiscByDisc() async throws {
        let library = try await Library.make()
        defer { library.discard() }
        let discs = [["Overture", "Zebra Crossing", "Middle Song"], ["Another Start", "Yesterday Again", "Finale"]]
        for (disc, titles) in discs.enumerated() {
            for (track, title) in titles.enumerated() {
                try await library.add("Live Set/CD \(disc + 1)/0\(track + 1).flac",
                                      song(title, by: "Band", on: "Live Set", year: 1999, track: track + 1))
            }
        }
        try await library.settle()
        // The store folds the two disc folders into ONE album (S10.8 C2) …
        let albums = try await library.store.albums()
        #expect(albums.map(\.trackCount) == [6])
        // … so its page has two songs numbered 1, two numbered 2 and two numbered 3. Each disc’s songs
        // must stay together: disc 1’s three, then disc 2’s — not track 1, track 1, track 2, track 2.
        let page = try await library.albumPage("Live Set")
        #expect(page.rows.map(\.title) == discs.flatMap(\.self))
    }

    @Test("MINOR — a genre page keeps each album’s songs in the album’s playing order")
    func genrePageKeepsAlbumOrder() async throws {
        let library = try await Library.make()
        defer { library.discard() }
        // “Mixed”: tracks 1–2 tagged disc 1, tracks 3–4 with no disc tag. “Roja”: a song with no number.
        for track in 1 ... 4 {
            try await library.add("Mixed/0\(track).flac", song("Mixed \(track)", on: "Mixed", year: 2000,
                                                               disc: track <= 2 ? 1 : nil, track: track))
        }
        try await library.add("Roja/bonus.flac", song("Roja Bonus", on: "Roja", year: 1992))
        for track in 1 ... 2 {
            try await library.add("Roja/0\(track).flac", song("Roja \(track)", on: "Roja", year: 1992, track: track))
        }
        try await library.settle()
        let genre = try await library.genrePage("Film")
        for album in ["Mixed", "Roja"] {
            let onAlbumPage = try await library.albumPage(album).rows.map(\.title)
            let onGenrePage = genre.rows.filter { $0.albumName == album }.map(\.title)
            #expect(onGenrePage == onAlbumPage, "“\(album)” on the genre page")
        }
    }

    @Test("MINOR — an artist’s (and a genre’s) album order does not depend on the scan order")
    func albumOrderDoesNotDependOnScanOrder() async throws {
        let albums = [("Alpha", 1990), ("Zulu", 2010)]
        var artistPages: [[String]] = []
        var genrePages: [[String]] = []
        // The same four songs, scanned “Alpha” first, then “Zulu” first.
        for scanOrder in [albums, Array(albums.reversed())] {
            let library = try await Library.make()
            defer { library.discard() }
            for (album, year) in scanOrder {
                for track in 1 ... 2 {
                    try await library.add("\(album)/0\(track).flac",
                                          song("\(album) \(track)", on: album, year: year, track: track))
                }
            }
            try await library.settle()
            try await artistPages.append(library.artistPage("Rahman").rows.map(\.title))
            try await genrePages.append(library.genrePage("Film").rows.map(\.title))
        }
        // Today both pages list albums by their store row id — whichever the scan happened to reach first.
        #expect(artistPages[0] == artistPages[1], "the artist page")
        #expect(genrePages[0] == genrePages[1], "the genre page")
    }

    // MARK: What an artist page shows of an album

    @Test("MINOR — an artist page’s album header shows the ALBUM’s year, as the album’s own page does")
    func artistPageHeaderShowsTheAlbumsYear() async throws {
        let library = try await Library.make()
        defer { library.discard() }
        try await addRahman(to: library)
        let shown = try await headerYears(library.artistPage("Rahman"))
        // “Bombay” is 1995 (its bonus song has no year); “Hits” is 1992 (Rahman’s one song on it is 1974).
        for album in try await library.store.albums() where shown[album.id] != nil {
            let albumYear = album.year > 0 ? String(album.year) : "-"
            #expect(shown[album.id] == albumYear, "“\(album.title)”: the album’s page says \(albumYear)")
        }
    }

    @Test("MINOR — the songs with no album carry no year on their “Unknown Album” header")
    func looseSongsHeaderHasNoYear() async throws {
        let library = try await Library.make()
        defer { library.discard() }
        try await addRahman(to: library)
        let shown = try await headerYears(library.artistPage("Rahman"))
        // The header names a bucket of unrelated songs; today it wears the first one’s year (“· 2001”).
        #expect(shown[FacetAlbumGrouping.noAlbumID] == "-")
    }

    @Test("MINOR — a song with no track number shows none on the artist page, when its album has numbers")
    func untaggedSongShowsNoNumberOnTheArtistPage() async throws {
        let library = try await Library.make()
        defer { library.discard() }
        try await library.add("Hits/01.flac", compilationSong("One", by: "Other", year: 1992, track: 1))
        try await library.add("Hits/02.flac", compilationSong("Two", by: "Other", year: 1992, track: 2))
        try await library.add("Hits/guest.flac", compilationSong("Guest Song", by: "Guest", year: 1992, track: nil))
        try await library.settle()
        // `DetailTrackLayout`’s rule: “in an album that has some [numbers], an untagged song shows none — a
        // number made up from its place would read as its track”. The album’s page keeps it …
        #expect(try await numberShown(for: "Guest Song", on: library.albumPage("Hits")) == "blank")
        // … the artist’s page, which holds only Guest’s songs of that album, makes one up (“1”).
        #expect(try await numberShown(for: "Guest Song", on: library.artistPage("Guest")) == "blank")
    }
}

// MARK: - Sprint E break-it (the selection kit, shared by Songs and the detail pages)

@Suite("Sprint E break-it — the selection kit after ⌘A")
struct ListSelectionBreakItTests {
    private let rows: [Int64] = [1, 2, 3, 4, 5]

    /// Select All on a page just opened: nothing clicked yet, so no anchor.
    private func allSelected() -> ListSelection<Int64> {
        var selection = ListSelection<Int64>()
        selection.selectAll(in: rows)
        return selection
    }

    @Test("MINOR — ⇧ after ⌘A extends the selection: it never collapses Select All to one row")
    func shiftAfterSelectAll() {
        var arrow = allSelected()
        arrow.move(.step(1), extend: true, in: rows) // ⇧↓
        #expect(arrow.ids.count > 1, "⌘A then ⇧↓ left only \(arrow.ids.sorted())")

        var end = allSelected()
        end.move(.last, extend: true, in: rows) // ⇧End
        #expect(end.ids.count > 1, "⌘A then ⇧End left only \(end.ids.sorted())")

        var click = allSelected()
        click.click(4, extend: true, toggle: false, in: rows) // ⇧-click
        #expect(click.ids.count > 1, "⌘A then ⇧-click left only \(click.ids.sorted())")
        #expect(click.contains(4))
    }
}
