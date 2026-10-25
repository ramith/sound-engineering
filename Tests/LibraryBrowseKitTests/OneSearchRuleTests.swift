import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import Testing

// MARK: - One search rule: the same query finds the same items in every tab and in ⌘F (US-R1F-14)

/// The founder's decision (2026-10-25): one word-start rule everywhere — each tab keeps its own sort, ⌘F's
/// results are ranked, "eyon" no longer finds "Beyoncé" in the Albums / Artists / Genres filters. Over a
/// real store, real scan and the tabs' own membership functions: the Songs search (the index), the Albums,
/// Artists, Genres and Playlists Filters (`FacetTextFilter` on `LibrarySearch`'s keys) and ⌘F's sections
/// (`LibrarySearch.results`) keep exactly the same items for every query — and the in-memory rule over a
/// song's own texts agrees with the index on every song.
@Suite("One search rule — every tab and ⌘F agree (US-R1F-14)", .serialized, .timeLimit(.minutes(3)))
struct OneSearchRuleTests {
    /// "Sri" written with its zero-width joiner, and without.
    private static let sriWithJoiner = "\u{0DC1}\u{0DCA}\u{200D}\u{0DBB}\u{0DD3}"
    private static let sriWithoutJoiner = "\u{0DC1}\u{0DCA}\u{0DBB}\u{0DD3}"

    /// One song of the fixture library.
    private struct Song {
        let title: String
        let artist: String
        let album: String
        let genre: String
    }

    private static let songs = [
        Song(title: "Halo", artist: "Beyoncé", album: "I Am... Sasha Fierce", genre: "Pop"),
        Song(title: "Formation", artist: "Beyoncé", album: "Lemonade", genre: "R&B"),
        Song(title: "Beyond the Sea", artist: "Bobby Darin", album: "That's All", genre: "Jazz"),
        Song(title: "Rock and Roll", artist: "Led Zeppelin", album: "Led Zeppelin IV", genre: "Rock"),
        Song(title: "\(sriWithJoiner) ලංකා මාතා", artist: "Ananda Samarakoon", album: "ජාතික ගීය", genre: "Rock"),
        Song(title: "මාල", artist: "අමරදේව", album: "ගීත", genre: "Sinhala"),
        Song(title: "මිල", artist: "අමරදේව", album: "ගීත", genre: "Sinhala"),
        Song(title: "Cafe\u{301} del Mar", artist: "Energy 52", album: "Cafe\u{301} del Mar", genre: "Trance"),
    ]

    private static let playlistNames = ["Rock", "Beyond Words", "\(sriWithoutJoiner) Favourites", "Café Mornings"]

    /// The library: the songs scanned, tagged, and the playlists made.
    private func library() async throws -> MusicFolder {
        let folder = try await MusicFolder.make("one-rule")
        let files = try folder.songs(in: "All", count: Self.songs.count)
        _ = try await LibraryScanner().scan(root: folder.music, folderID: folder.root, into: folder.store)
        for (file, song) in zip(files, Self.songs) {
            let id = try #require(try await folder.store.track(url: file)).id
            try await folder.store.applyMetadata(
                TrackMetadata(title: song.title, artistName: song.artist, albumTitle: song.album, genres: [song.genre]),
                forTrack: id
            )
        }
        for name in Self.playlistNames {
            _ = try await folder.store.createPlaylist(name: name)
        }
        return folder
    }

    /// What every tab keeps for a query, and what ⌘F lists — as id sets.
    private struct Membership: Equatable {
        var songs: Set<Int64>
        var albums: Set<Int64>
        var artists: Set<Int64>
        var genres: Set<Int64>
        var playlists: Set<Int64>
    }

    /// The tabs' membership for `query`: the Songs search, then each list's Filter.
    private func tabs(_ query: String, _ store: LibraryStore) async throws -> (Membership, LibrarySearch.Lists) {
        let albums = try await store.albums(sortedBy: .title)
        let artists = try await store.artists()
        let genres = try await store.genres()
        let playlists = try await PlaylistBrowseVisibility.userVisible(store.playlists())
        let songIDs = try await store.searchMatchingIDs(query)
        let membership = Membership(
            songs: songIDs,
            albums: Set(FacetTextFilter.filter(albums, query: query, candidates: LibrarySearch.albumKeys).map(\.id)),
            artists: Set(FacetTextFilter.filter(artists, query: query, candidates: LibrarySearch.artistKeys).map(\.id)),
            genres: Set(FacetTextFilter.filter(genres, query: query, candidates: LibrarySearch.genreKeys).map(\.id)),
            playlists: Set(FacetTextFilter.filter(playlists, query: query,
                                                  candidates: LibrarySearch.playlistKeys).map(\.id))
        )
        let found = try await Array(store.tracksDisplay(ids: Array(songIDs)).values)
        return (membership, LibrarySearch.Lists(songs: found, albums: albums, artists: artists, genres: genres,
                                                playlists: playlists))
    }

    /// ⌘F's sections for `query` over the same lists, as id sets.
    private func commandF(_ query: String, _ lists: LibrarySearch.Lists) -> Membership {
        let results = LibrarySearch.results(for: query, in: lists)
        return Membership(songs: Set(results.songs.map(\.id)), albums: Set(results.albums.map(\.id)),
                          artists: Set(results.artists.map(\.id)), genres: Set(results.genres.map(\.id)),
                          playlists: Set(results.playlists.map(\.id)))
    }

    private static let queries = [
        "beyo", "eyon", "rock", "roll rock", "lemo beyo", "café", "Cafe\u{301}", "මා", "ගී",
        sriWithJoiner, sriWithoutJoiner, "\(sriWithoutJoiner) ලං", "zeppelin iv", "!!!",
    ]

    @Test("every query: the Songs search, the four Filters and ⌘F keep the same items")
    func sameMembershipEverywhere() async throws {
        let folder = try await library()
        defer { folder.discard() }
        for query in Self.queries {
            let (tabs, lists) = try await tabs(query, folder.store)
            #expect(commandF(query, lists) == tabs, "“\(query)”")
        }
    }

    @Test("the in-memory rule over a song's own texts agrees with the index, song by song")
    func ruleAgreesWithIndex() async throws {
        let folder = try await library()
        defer { folder.discard() }
        let all = try await folder.store.allTracksDisplay(sortedBy: .artistAlbumTrack, limit: nil)
        for query in Self.queries {
            let indexed = try await folder.store.searchMatchingIDs(query)
            let compiled = SearchRule.Query(query)
            for song in all {
                let texts = [song.title, song.artistName, song.albumName ?? "", song.genreName ?? ""]
                #expect(compiled.matches(texts) == indexed.contains(song.id), "“\(query)” on “\(song.title)”")
            }
        }
    }

    @Test("“beyo” finds Beyoncé in every tab and ⌘F; “eyon” finds her nowhere")
    func beyoAndEyon() async throws {
        let folder = try await library()
        defer { folder.discard() }
        let (beyo, _) = try await tabs("beyo", folder.store)
        let titles = try await folder.store.tracksDisplay(ids: Array(beyo.songs)).values.map(\.title)
        #expect(Set(titles) == ["Halo", "Formation", "Beyond the Sea"]) // by artist, and a title's word
        let artists = try await folder.store.artists().filter { beyo.artists.contains($0.id) }.map(\.name)
        #expect(Set(artists) == ["Beyoncé"])
        let albums = try await folder.store.albums(sortedBy: .title).filter { beyo.albums.contains($0.id) }
        #expect(Set(albums.map(\.title)) == ["I Am... Sasha Fierce", "Lemonade"])
        let playlists = try await folder.store.playlists().filter { beyo.playlists.contains($0.id) }.map(\.name)
        #expect(playlists == ["Beyond Words"])
        let (eyon, _) = try await tabs("eyon", folder.store)
        #expect(eyon == Membership(songs: [], albums: [], artists: [], genres: [], playlists: []))
    }

    @Test("a Sinhala query finds the same title typed with or without the joiner, and NFD as NFC")
    func sinhalaEverywhere() async throws {
        let folder = try await library()
        defer { folder.discard() }
        let (withJoiner, _) = try await tabs(Self.sriWithJoiner, folder.store)
        let (withoutJoiner, _) = try await tabs(Self.sriWithoutJoiner, folder.store)
        #expect(withJoiner == withoutJoiner)
        #expect(withJoiner.songs.count == 1)
        #expect(withJoiner.playlists.count == 1)
        let (composed, _) = try await tabs("café", folder.store)
        let (decomposed, _) = try await tabs("Cafe\u{301}", folder.store)
        #expect(composed == decomposed)
        #expect(composed.songs.count == 1)
        #expect(composed.albums.count == 1)
        #expect(composed.playlists.count == 1)
    }
}
