import Foundation
import LibraryStore

// MARK: - LibrarySearch (R1.1-B, US-R1F-14 — ⌘F's results: the tabs' membership, ranked)

/// ⌘F's search over the whole library: songs, albums, artists, genres and playlists. One search rule
/// (`SearchRule`; founder 2026-10-25): an item is in a section exactly when the same query typed into that
/// tab's Filter keeps it — the songs the Songs search finds, the albums the Albums Filter keeps, and so on
/// (the keys below are the ones the tabs filter on) — so ⌘F and the tabs can never disagree on
/// membership. Where a tab keeps its own sort, ⌘F RANKS each section by one relevance rule
/// (`SearchRelevance`), the same for every kind of item: a playlist named "Rock" and the genre "Rock" both
/// lead their sections.
public enum LibrarySearch {
    // MARK: The keys each list matches on — shared with the tabs' Filters

    /// An album matches on its title or its artist.
    public static func albumKeys(_ album: AlbumFacet) -> [String] {
        [album.title, album.albumArtist]
    }

    /// An artist matches on its name.
    public static func artistKeys(_ artist: ArtistFacet) -> [String] {
        [artist.name]
    }

    /// A genre matches on its name.
    public static func genreKeys(_ genre: GenreFacet) -> [String] {
        [genre.name]
    }

    /// A playlist matches on its name.
    public static func playlistKeys(_ playlist: Playlist) -> [String] {
        [playlist.name]
    }

    // MARK: Results

    /// What ⌘F searches: the songs the Songs search found for the query (the index decides their
    /// membership), and the other lists whole, as their tabs list them.
    public struct Lists: Sendable {
        public var songs: [LibraryTrackDisplay]
        public var albums: [AlbumFacet]
        public var artists: [ArtistFacet]
        public var genres: [GenreFacet]
        public var playlists: [Playlist]

        public init(songs: [LibraryTrackDisplay] = [], albums: [AlbumFacet] = [], artists: [ArtistFacet] = [],
                    genres: [GenreFacet] = [], playlists: [Playlist] = []) {
            self.songs = songs
            self.albums = albums
            self.artists = artists
            self.genres = genres
            self.playlists = playlists
        }
    }

    /// ⌘F's results for `query` over `lists`: each list keeps what its tab's Filter keeps — of what the tab
    /// lists (a 0-song album, artist or genre is in no tab, `FacetListVisibility`) — and every section is
    /// ranked by `SearchRelevance`. A query with no word in it finds nothing.
    public static func results(for query: String, in lists: Lists) -> LibrarySearchResults {
        let compiled = SearchRule.Query(query)
        guard !compiled.isEmpty else { return .empty }
        let none: (Any) -> [String] = { _ in [] }
        let albums = lists.albums.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) }
        let artists = lists.artists.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) }
        let genres = lists.genres.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) }
        return LibrarySearchResults(
            songs: ranked(lists.songs, by: compiled, name: \.title, others: songOthers),
            albums: ranked(kept(albums, by: compiled, keys: albumKeys), by: compiled, name: \.title) {
                [$0.albumArtist]
            },
            artists: ranked(kept(artists, by: compiled, keys: artistKeys), by: compiled, name: \.name, others: none),
            genres: ranked(kept(genres, by: compiled, keys: genreKeys), by: compiled, name: \.name, others: none),
            playlists: ranked(kept(lists.playlists, by: compiled, keys: playlistKeys), by: compiled, name: \.name,
                              others: none)
        )
    }

    /// A song's texts beside its title, as the index holds them: its artist, album and genre.
    private static func songOthers(_ song: LibraryTrackDisplay) -> [String] {
        [song.artistName, song.albumName ?? "", song.genreName ?? ""]
    }

    /// The items a tab's Filter keeps for `query` — the membership ⌘F shares with the tab.
    private static func kept<Item>(_ items: [Item], by query: SearchRule.Query, keys: (Item) -> [String]) -> [Item] {
        items.filter { query.matches(keys($0)) }
    }

    /// `items` in rank order: by relevance (an item the rule finds only through texts it cannot see — a
    /// song's second genre, held by the index — ranks last), then by name as Finder sorts, then by id.
    static func ranked<Item: Identifiable>(
        _ items: [Item], by query: SearchRule.Query, name: (Item) -> String, others: (Item) -> [String]
    ) -> [Item] where Item.ID == Int64 {
        let scored = items.map { item in
            (item: item, name: name(item),
             relevance: SearchRelevance(name: name(item), others: others(item), query: query) ?? .unseen)
        }
        return scored.sorted { lhs, rhs in
            if lhs.relevance != rhs.relevance {
                return lhs.relevance < rhs.relevance
            }
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.item.id < rhs.item.id
            }
        }.map(\.item)
    }
}

/// ⌘F's results, each section ranked (`LibrarySearch.results`).
public struct LibrarySearchResults: Sendable, Equatable {
    public let songs: [LibraryTrackDisplay]
    public let albums: [AlbumFacet]
    public let artists: [ArtistFacet]
    public let genres: [GenreFacet]
    public let playlists: [Playlist]

    public static let empty = LibrarySearchResults(songs: [], albums: [], artists: [], genres: [], playlists: [])

    public init(songs: [LibraryTrackDisplay], albums: [AlbumFacet], artists: [ArtistFacet], genres: [GenreFacet],
                playlists: [Playlist]) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
        self.genres = genres
        self.playlists = playlists
    }

    /// Whether no section holds anything.
    public var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty && genres.isEmpty && playlists.isEmpty
    }

    /// How many items `section` holds.
    public func count(of section: LibrarySearchSection) -> Int {
        switch section {
        case .songs: songs.count
        case .albums: albums.count
        case .artists: artists.count
        case .genres: genres.count
        case .playlists: playlists.count
        }
    }

    /// The first `limit` items of `section`, in rank order — the rows ⌘F shows of it.
    public func items(of section: LibrarySearchSection, limit: Int) -> [LibrarySearchItem] {
        switch section {
        case .songs: songs.prefix(limit).map { .song($0.id) }
        case .albums: albums.prefix(limit).map { .album($0.id) }
        case .artists: artists.prefix(limit).map { .artist($0.id) }
        case .genres: genres.prefix(limit).map { .genre($0.id) }
        case .playlists: playlists.prefix(limit).map { .playlist($0.id) }
        }
    }

    /// Every row ⌘F shows, section by section in `LibrarySearchSection` order — the order its keyboard
    /// cursor walks.
    public func shownItems(limit: (LibrarySearchSection) -> Int) -> [LibrarySearchItem] {
        LibrarySearchSection.allCases.flatMap { items(of: $0, limit: limit($0)) }
    }
}

/// ⌘F's sections, in the order they show: the rail's order (Songs, Albums, Artists, Genres), then
/// Playlists.
public enum LibrarySearchSection: CaseIterable, Sendable {
    case songs
    case albums
    case artists
    case genres
    case playlists
}

/// One row of ⌘F's results: the item it opens or plays.
public enum LibrarySearchItem: Hashable, Sendable {
    case song(Int64)
    case album(Int64)
    case artist(Int64)
    case genre(Int64)
    case playlist(Int64)
}

// MARK: - SearchRelevance — the one ranking rule

/// How closely an item matches a query — what ⌘F ranks every section by, the same for a song, an album,
/// an artist, a genre and a playlist. Lower is closer. By tier first:
///   1. EXACT — the item's name is the query, word for word ("rock" → "Rock");
///   2. NAME STARTS — the name starts with the query: its first words are the query's, the last one begun
///      ("beyo" → "Beyoncé", "rock and" → "Rock and Roll");
///   3. IN NAME — every query word starts a word of the name, anywhere ("roll" → "Rock and Roll");
///   4. ELSEWHERE — the item is found through its other texts (a song by its artist, an album by its
///      artist).
/// Within a tier, a name of fewer words, then a shorter one, is closer.
public struct SearchRelevance: Comparable, Sendable {
    /// How the query meets the item (see the type's comment).
    public enum Tier: Int, Comparable, Sendable {
        case exact
        case nameStarts
        case inName
        case elsewhere
        /// Found by the index through a text this rule does not see (a song's second genre).
        case unseen

        public static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let tier: Tier
    /// The name's word count — fewer is a closer match.
    let nameWordCount: Int
    /// The name's folded length, in UTF-8 bytes — shorter is a closer match.
    let nameLength: Int

    /// The rank of an item the index found through a text the rule does not see.
    static let unseen = SearchRelevance(tier: .unseen, nameWordCount: .max, nameLength: .max)

    private init(tier: Tier, nameWordCount: Int, nameLength: Int) {
        self.tier = tier
        self.nameWordCount = nameWordCount
        self.nameLength = nameLength
    }

    /// The relevance of an item named `name`, with `others` its other texts, to `query` — nil when the
    /// query does not find it (or has no word).
    public init?(name: String, others: [String] = [], query: SearchRule.Query) {
        let nameWords = SearchRule.words(of: name)
        let queryWords = query.words
        guard !queryWords.isEmpty else { return nil }
        let tier: Tier
        if nameWords == queryWords {
            tier = .exact
        } else if Self.starts(nameWords, with: queryWords) {
            tier = .nameStarts
        } else if query.matches(words: nameWords) {
            tier = .inName
        } else if query.matches(words: nameWords + others.flatMap(SearchRule.words(of:))) {
            tier = .elsewhere
        } else {
            return nil
        }
        self.init(tier: tier, nameWordCount: nameWords.count,
                  nameLength: nameWords.reduce(0) { $0 + $1.utf8.count })
    }

    /// Whether `nameWords` begin with `queryWords`: every query word but the last is the name's word at
    /// its place, and the last starts the next.
    private static func starts(_ nameWords: [String], with queryWords: [String]) -> Bool {
        guard let last = queryWords.last, nameWords.count >= queryWords.count else { return false }
        let leading = queryWords.count - 1
        return Array(nameWords.prefix(leading)) == Array(queryWords.prefix(leading))
            && SearchRule.word(nameWords[leading], startsWith: last)
    }

    public static func < (lhs: SearchRelevance, rhs: SearchRelevance) -> Bool {
        (lhs.tier, lhs.nameWordCount, lhs.nameLength) < (rhs.tier, rhs.nameWordCount, rhs.nameLength)
    }
}
