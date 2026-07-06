// LibraryStore+FacetDrilldown — S9.1 facet drill-downs + single-facet reads (design §3).
//
// Adds the browse drill-downs (`albums(byArtist:)`, `albums(inGenre:)`,
// `albums(inYear:)`, `years()`) and the detail-header single-facet reads
// (`album(id:)`, `artist(id:)`) ALONGSIDE the existing `albums()`/`artists()`/
// `genres()` list reads (LibraryStore+Facets).
//
// The album/artist SELECT + row mapper live here as SHARED builders that BOTH the list
// reads (LibraryStore+Facets delegates to them) and these drill-downs use — so
// `album(id:)`/`artist(id:)` return a facet BYTE-IDENTICAL to the matching list entry
// (BR3) by construction, and the id-0 unknown-artist sentinel is excluded uniformly
// (BR3b — the exclusion lives in `artistSelectSQL`, so no artist read can leak it).
//
// All reads: actor-isolated, `throws`, `Sendable` returns, NO filesystem access, fully
// synchronous per the actor invariant. Supporting indexes (`idx_albums_artist`,
// `idx_albums_year`, `idx_tracks_album`, `idx_trackgenres_genre`) keep every hot read
// index-driven (BR5).

import Foundation

public extension LibraryStore {
    // MARK: - Shared album/artist SQL fragments

    internal static let albumTitleOrder = "al.title COLLATE NOCASE ASC, al.id ASC"
    internal static let albumYearOrder = "al.year ASC, al.title COLLATE NOCASE ASC, al.id ASC"
    internal static let albumsInYearWhere = "WHERE al.year = ?"
    /// The genre-membership sub-select for `albums(inGenre:)` — `t2` aliases `tracks`
    /// inside it (so the BR5 scan detector must also flag a `SCAN t2`). Shared so the
    /// read + its EXPLAIN reproduce identical SQL; the DISTINCT sub-select means an album
    /// with several in-genre tracks lists ONCE (no fan-out).
    internal static let albumsInGenreWhere =
        "WHERE al.id IN (SELECT DISTINCT t2.album_id FROM tracks t2 "
            + "JOIN track_genres tg ON tg.track_id = t2.id "
            + "WHERE tg.genre_id = ? AND t2.album_id IS NOT NULL)"
    internal static let artistNameOrder = "ar.name COLLATE NOCASE ASC, ar.id ASC"
    internal static let artistSortNameOrder =
        "ar.sort_name COLLATE NOCASE ASC, ar.name COLLATE NOCASE ASC, ar.id ASC"

    // MARK: - Album SELECT builder + mapper (shared with `albums()` in +Facets)

    /// Assemble the `AlbumFacet` SELECT: `albums al` LEFT-JOINed to `artists` (resolved
    /// album-artist name) and `tracks` (LEFT JOIN so a zero-track album still lists with
    /// count 0), filtered by `whereClause`, grouped per album, ordered, optionally
    /// paginated. A pure static builder (shared so the drill-downs and the list read can
    /// never drift, and the EXPLAIN hook can reproduce it byte-for-byte).
    internal static func albumSelectSQL(whereClause: String, order: String, limited: Bool) -> String {
        var sql = "SELECT al.id, al.title, al.album_artist_id, ar.name, al.year, "
        sql += "count(t.id) AS track_count, al.artwork_key "
        sql += "FROM albums al "
        sql += "LEFT JOIN artists ar ON ar.id = al.album_artist_id "
        sql += "LEFT JOIN tracks t ON t.album_id = al.id"
        if !whereClause.isEmpty { sql += " " + whereClause }
        sql += " GROUP BY al.id ORDER BY \(order)"
        if limited { sql += " LIMIT ? OFFSET ?" }
        sql += ";"
        return sql
    }

    /// Decode the current row (projected as `albumSelectSQL`) into an `AlbumFacet`.
    internal func mapAlbumRow(_ statement: SQLiteStatement) -> AlbumFacet {
        AlbumFacet(
            id: statement.columnInt64(0),
            title: statement.columnText(1) ?? "",
            albumArtistID: statement.columnInt64(2),
            albumArtist: statement.columnText(3) ?? "",
            year: statement.columnInt(4),
            trackCount: statement.columnInt(5),
            artworkKey: statement.columnText(6)
        )
    }

    /// Prepare the assembled album SELECT, bind `bind`, and map every row — the shared
    /// engine for `albums()` and every album drill-down.
    internal func fetchAlbums(
        whereClause: String, order: String, limited: Bool,
        bind: (SQLiteStatement) throws -> Void = { _ in }
    ) throws -> [AlbumFacet] {
        let statement = try connection.prepare(
            LibraryStore.albumSelectSQL(whereClause: whereClause, order: order, limited: limited)
        )
        defer { statement.finalize() }
        try bind(statement)
        var facets: [AlbumFacet] = []
        while try statement.step() {
            facets.append(mapAlbumRow(statement))
        }
        return facets
    }

    // MARK: - Artist SELECT builder + mapper (shared with `artists()` in +Facets)

    /// Assemble the `ArtistFacet` SELECT. The id-0 unknown-artist sentinel is ALWAYS
    /// excluded here (`WHERE ar.id <> unknownArtistID`), so no artist read — list or
    /// single-facet — can surface it (BR3b). `extraWhere` is appended with `AND`.
    internal static func artistSelectSQL(extraWhere: String, order: String, limited: Bool) -> String {
        var sql = "SELECT ar.id, ar.name, ar.sort_name, count(t.id) AS track_count "
        sql += "FROM artists ar "
        sql += "LEFT JOIN tracks t ON t.artist_id = ar.id "
        sql += "WHERE ar.id <> \(unknownArtistID)"
        if !extraWhere.isEmpty { sql += " " + extraWhere }
        sql += " GROUP BY ar.id ORDER BY \(order)"
        if limited { sql += " LIMIT ? OFFSET ?" }
        sql += ";"
        return sql
    }

    /// Decode the current row (projected as `artistSelectSQL`) into an `ArtistFacet`.
    internal func mapArtistRow(_ statement: SQLiteStatement) -> ArtistFacet {
        ArtistFacet(
            id: statement.columnInt64(0),
            name: statement.columnText(1) ?? ""
        )
    }

    /// Prepare the assembled artist SELECT, bind `bind`, and map every row — the shared
    /// engine for `artists()` and `artist(id:)`.
    internal func fetchArtists(
        extraWhere: String, order: String, limited: Bool,
        bind: (SQLiteStatement) throws -> Void = { _ in }
    ) throws -> [ArtistFacet] {
        let statement = try connection.prepare(
            LibraryStore.artistSelectSQL(extraWhere: extraWhere, order: order, limited: limited)
        )
        defer { statement.finalize() }
        try bind(statement)
        var facets: [ArtistFacet] = []
        while try statement.step() {
            facets.append(mapArtistRow(statement))
        }
        return facets
    }

    // MARK: - Album drill-downs

    /// Albums CREDITED to `artistID` as album-artist (`album_artist_id`), ordered by
    /// `sortedBy` (year by default). This is the Music.app "Artist → Albums" lens —
    /// it includes an artist's compilations they front and correctly attributes
    /// "Various Artists" albums to that sentinel-free album-artist row. Uses
    /// `idx_albums_artist`.
    func albums(byArtist artistID: Int64, sortedBy sort: FacetSort = .year) throws -> [AlbumFacet] {
        try fetchAlbums(
            whereClause: "WHERE al.album_artist_id = ?",
            order: sort == .year ? LibraryStore.albumYearOrder : LibraryStore.albumTitleOrder,
            limited: false
        ) { try $0.bind(artistID, at: 1) }
    }

    /// Albums that contain at least one track in genre `genreID`, via a `track_genres`
    /// JOIN inside a DISTINCT sub-select — so an album with several tracks in the genre
    /// lists ONCE (no fan-out), and its `trackCount` is still the album's full count.
    func albums(inGenre genreID: Int64) throws -> [AlbumFacet] {
        try fetchAlbums(
            whereClause: LibraryStore.albumsInGenreWhere,
            order: LibraryStore.albumTitleOrder, limited: false
        ) { try $0.bind(genreID, at: 1) }
    }

    /// Albums released in `year` (the album row's `year`), title-ordered. Uses
    /// `idx_albums_year` (BR5).
    func albums(inYear year: Int) throws -> [AlbumFacet] {
        try fetchAlbums(
            whereClause: LibraryStore.albumsInYearWhere,
            order: LibraryStore.albumTitleOrder, limited: false
        ) { try $0.bind(Int64(year), at: 1) }
    }

    // MARK: - Year facet + single-facet detail reads

    /// Distinct non-null track years, DESCENDING — the Years sidebar facet. Uses
    /// `idx_tracks_year`.
    func years() throws -> [Int] {
        let statement = try connection.prepare(
            "SELECT DISTINCT year FROM tracks WHERE year IS NOT NULL ORDER BY year DESC;"
        )
        defer { statement.finalize() }
        var years: [Int] = []
        while try statement.step() {
            years.append(statement.columnInt(0))
        }
        return years
    }

    /// The single `AlbumFacet` for `albumID`, or `nil`. Byte-identical to the matching
    /// `albums()` entry (same shared builder) — a detail header reads it directly rather
    /// than client-side filtering a list (BR3).
    func album(id albumID: Int64) throws -> AlbumFacet? {
        try fetchAlbums(
            whereClause: "WHERE al.id = ?", order: LibraryStore.albumTitleOrder, limited: false
        ) { try $0.bind(albumID, at: 1) }.first
    }

    /// The single `ArtistFacet` for `artistID`, or `nil`. Byte-identical to the matching
    /// `artists()` entry; the id-0 sentinel resolves to `nil` (BR3/BR3b).
    func artist(id artistID: Int64) throws -> ArtistFacet? {
        try fetchArtists(
            extraWhere: "AND ar.id = ?", order: LibraryStore.artistNameOrder, limited: false
        ) { try $0.bind(artistID, at: 1) }.first
    }
}
