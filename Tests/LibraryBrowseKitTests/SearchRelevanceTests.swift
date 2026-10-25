import Foundation
import LibraryBrowseKit
import LibraryStore
import Testing

// MARK: - ⌘F's ranking — one relevance rule for every kind of item (US-R1F-14)

@Suite("SearchRelevance — ⌘F ranks every section by one rule")
struct SearchRelevanceTests {
    private func tier(_ name: String, _ query: String, others: [String] = []) -> SearchRelevance.Tier? {
        SearchRelevance(name: name, others: others, query: SearchRule.Query(query))?.tier
    }

    @Test("the tiers: exact, then the name's start, then a word of the name, then the item's other texts")
    func tiers() {
        #expect(tier("Rock", "rock") == .exact)
        #expect(tier("Rock and Roll", "rock and") == .nameStarts)
        #expect(tier("Beyoncé", "beyo") == .nameStarts)
        #expect(tier("Rock and Roll", "roll") == .inName)
        #expect(tier("Rock and Roll", "roll rock") == .inName)
        #expect(tier("Halo", "beyo", others: ["Beyoncé"]) == .elsewhere)
        #expect(tier("Halo", "eyon", others: ["Beyoncé"]) == nil)
        #expect(tier("Halo", "!!!") == nil)
    }

    @Test("within a tier, fewer words, then a shorter name, rank first")
    func tieBreaks() throws {
        let query = SearchRule.Query("rock")
        let rock = try #require(SearchRelevance(name: "Rock", query: query))
        let rockRoll = try #require(SearchRelevance(name: "Rock and Roll", query: query))
        let rockabilly = try #require(SearchRelevance(name: "Rockabilly", query: query))
        let rocks = try #require(SearchRelevance(name: "Rocks", query: query))
        #expect(rock < rocks) // exact before a name that starts with it
        #expect(rocks < rockabilly) // same tier and word count: shorter first
        #expect(rockabilly < rockRoll) // fewer words first
    }

    /// Counter-example 8 (plan check §6): a playlist named "Rock" and the genre "Rock" both appear in ⌘F,
    /// ranked by the same rule — each leads its section.
    @Test("a playlist “Rock” and the genre “Rock” both lead their sections, by the same rule")
    func rockPlaylistAndGenre() {
        let genres = [GenreFacet(id: 1, name: "Rock and Roll", trackCount: 3),
                      GenreFacet(id: 2, name: "Rock", trackCount: 1),
                      GenreFacet(id: 3, name: "Punk Rock", trackCount: 9),
                      GenreFacet(id: 4, name: "Jazz", trackCount: 2)]
        let playlists = [Playlist(id: 7, name: "Rocking Chair", isBuiltin: false, createdAt: 1, entryCount: 1),
                         Playlist(id: 8, name: "Rock", isBuiltin: false, createdAt: 2, entryCount: 4),
                         Playlist(id: 9, name: "Road Trip", isBuiltin: false, createdAt: 3, entryCount: 4)]
        let results = LibrarySearch.results(for: "rock", in: LibrarySearch.Lists(genres: genres, playlists: playlists))
        #expect(results.genres.map(\.name) == ["Rock", "Rock and Roll", "Punk Rock"])
        #expect(results.playlists.map(\.name) == ["Rock", "Rocking Chair"])
    }

    @Test("songs rank by their title first: a title that is the query leads, a song found by its artist trails")
    func songsRankByTitle() {
        let songs = [song(1, "Halo", artist: "Beyoncé"), song(2, "Beyond the Sea", artist: "Bobby Darin"),
                     song(3, "Beyoncé", artist: "Someone"), song(4, "Formation", artist: "Beyoncé")]
        let results = LibrarySearch.results(for: "beyo", in: LibrarySearch.Lists(songs: songs))
        #expect(results.songs.map(\.id) == [3, 2, 1, 4]) // the title starts it (1 word, then 3); then by artist
    }

    @Test("a query with no word ranks nothing; an empty result is empty")
    func noWord() {
        let genres = [GenreFacet(id: 1, name: "Rock", trackCount: 1)]
        #expect(LibrarySearch.results(for: "!!!", in: LibrarySearch.Lists(genres: genres)).isEmpty)
        #expect(LibrarySearch.results(for: "jazz", in: LibrarySearch.Lists(genres: genres)).isEmpty)
    }

    private func song(_ id: Int64, _ title: String, artist: String) -> LibraryTrackDisplay {
        LibraryTrackDisplay(
            id: id, url: URL(fileURLWithPath: "/m/\(id).flac"), title: title, artistID: nil, artistName: artist,
            albumID: nil, albumName: nil, format: "FLAC", trackNo: nil, durationMs: 1000, year: nil,
            artworkKey: nil, dateAdded: 0, sampleRate: nil, bitDepth: nil, discNo: nil, fileSize: 1, playCount: 0,
            lastPlayed: nil, albumArtistName: nil, genreName: nil
        )
    }
}

// MARK: - The rows ⌘F shows

@Suite("LibrarySearchResults — the rows ⌘F shows, section by section")
struct LibrarySearchShownTests {
    @Test("each section shows its first rows, in the rail's order, then Playlists")
    func shownItems() {
        let genres = (1 ... 7).map { GenreFacet(id: Int64($0), name: "Rock \($0)", trackCount: 1) }
        let playlists = [Playlist(id: 9, name: "Rock", isBuiltin: false, createdAt: 1, entryCount: 1)]
        let results = LibrarySearch.results(for: "rock", in: LibrarySearch.Lists(genres: genres, playlists: playlists))
        let shown = results.shownItems { $0 == .genres ? 3 : 5 }
        #expect(shown == [.genre(1), .genre(2), .genre(3), .playlist(9)])
        #expect(results.count(of: .genres) == 7)
    }

    @Test("an album, artist or genre with no songs is in no tab, so not in ⌘F")
    func zeroSongFacetsHidden() {
        let genres = [GenreFacet(id: 1, name: "Rock", trackCount: 0),
                      GenreFacet(id: 2, name: "Rockabilly", trackCount: 2)]
        let results = LibrarySearch.results(for: "rock", in: LibrarySearch.Lists(genres: genres))
        #expect(results.genres.map(\.id) == [2])
    }
}
