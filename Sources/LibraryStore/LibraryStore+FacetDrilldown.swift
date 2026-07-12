// LibraryStore+FacetDrilldown — S9.1 facet drill-downs + single-facet reads (design §3), GRDB-backed.
//
// The browse drill-downs (`albums(byArtist:)`, `albums(inGenre:)`) and the detail-header
// single-facet reads (`album(id:)`, `artist(id:)`, `genre(id:)`) ALONGSIDE the existing
// `albums()`/`artists()`/`genres()` list reads (LibraryStore+Facets).
//
// The album/artist SELECT builders live here as SHARED statics that BOTH the list reads and
// these drill-downs consume — so `album(id:)`/`artist(id:)` return a facet BYTE-IDENTICAL to
// the matching list entry (BR3), and the id-0 sentinel is excluded uniformly (BR3b — in
// `artistSelectSQL`). `AlbumFacet`/`ArtistFacet` decode via `FetchableRecord`. Supporting
// indexes (`idx_albums_artist`, `idx_albums_year`, `idx_tracks_album`, `idx_trackgenres_genre`)
// keep every hot read index-driven (BR5).

import Foundation
import GRDB

// MARK: - Facet row decoding (FetchableRecord)

extension AlbumFacet: FetchableRecord {
    /// Decode a row projected as `LibraryStore.albumSelectSQL` (positional).
    public init(row: Row) {
        self.init(
            id: row[0], title: row[1] ?? "", albumArtistID: row[2], albumArtist: row[3] ?? "",
            year: row[4], trackCount: row[5], artworkKey: row[6]
        )
    }
}

extension ArtistFacet: FetchableRecord {
    /// Decode a row projected as `LibraryStore.artistSelectSQL`. Column 3 is
    /// `count(t.id) AS track_count` (track-artist lens); column 4 the representative `artwork_key`.
    public init(row: Row) {
        self.init(id: row[0], name: row[1] ?? "", trackCount: row[3], artworkKey: row[4])
    }
}

public extension LibraryStore {
    // MARK: - Shared album/artist SQL fragments

    internal static let albumTitleOrder = "al.title COLLATE NOCASE ASC, al.id ASC"
    internal static let albumYearOrder = "al.year ASC, al.title COLLATE NOCASE ASC, al.id ASC"
    /// The genre-membership sub-select for `albums(inGenre:)` — `t2` aliases `tracks` inside it
    /// (so the BR5 scan detector must also flag a `SCAN t2`). The DISTINCT sub-select means an
    /// album with several in-genre tracks lists ONCE (no fan-out).
    internal static let albumsInGenreWhere =
        "WHERE al.id IN (SELECT DISTINCT t2.album_id FROM tracks t2 "
            + "JOIN track_genres tg ON tg.track_id = t2.id "
            + "WHERE tg.genre_id = ? AND t2.album_id IS NOT NULL)"
    internal static let artistNameOrder = "ar.name COLLATE NOCASE ASC, ar.id ASC"
    internal static let artistSortNameOrder =
        "ar.sort_name COLLATE NOCASE ASC, ar.name COLLATE NOCASE ASC, ar.id ASC"

    /// The single-`GenreFacet` detail read — same `count(DISTINCT tg.track_id)` semantics as `genres()`.
    private static let selectGenreByIDSQL = """
    SELECT g.id, g.name, count(DISTINCT tg.track_id) AS track_count
    FROM genres g
    LEFT JOIN track_genres tg ON tg.genre_id = g.id
    WHERE g.id = ?
    GROUP BY g.id;
    """

    // MARK: - Album SELECT builder (shared with `albums()` in +Facets)

    /// Assemble the `AlbumFacet` SELECT: `albums al` LEFT-JOINed to `artists` (resolved
    /// album-artist name) and `tracks` (LEFT JOIN so a zero-track album still lists with count
    /// 0), filtered by `whereClause`, grouped per album, ordered, optionally paginated. A pure
    /// static builder (shared so the drill-downs and the list read never drift, and the EXPLAIN
    /// hook reproduces it byte-for-byte).
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

    /// Fetch `AlbumFacet`s for the assembled album SELECT — the shared engine for `albums()`
    /// and every album drill-down.
    internal static func fetchAlbums(
        _ db: Database, whereClause: String, order: String, limited: Bool, arguments: StatementArguments
    ) throws -> [AlbumFacet] {
        try AlbumFacet.fetchAll(
            db, sql: albumSelectSQL(whereClause: whereClause, order: order, limited: limited), arguments: arguments
        )
    }

    // MARK: - Artist SELECT builder (shared with `artists()` in +Facets)

    /// Assemble the `ArtistFacet` SELECT. The id-0 unknown-artist sentinel is ALWAYS excluded
    /// here (`WHERE ar.id <> unknownArtistID`), so no artist read can surface it (BR3b).
    /// `extraWhere` is appended with `AND`.
    internal static func artistSelectSQL(extraWhere: String, order: String, limited: Bool) -> String {
        var sql = "SELECT ar.id, ar.name, ar.sort_name, count(t.id) AS track_count, "
        // Representative album cover (index 4): any album containing one of this artist's tracks
        // that has artwork. Correlated per artist row; `idx_tracks_artist` seeks t2 — no scan.
        sql += "(SELECT al.artwork_key FROM tracks t2 JOIN albums al ON al.id = t2.album_id "
        sql += "WHERE t2.artist_id = ar.id AND al.artwork_key IS NOT NULL LIMIT 1) AS artwork_key "
        sql += "FROM artists ar "
        sql += "LEFT JOIN tracks t ON t.artist_id = ar.id "
        sql += "WHERE ar.id <> \(unknownArtistID)"
        if !extraWhere.isEmpty { sql += " " + extraWhere }
        sql += " GROUP BY ar.id ORDER BY \(order)"
        if limited { sql += " LIMIT ? OFFSET ?" }
        sql += ";"
        return sql
    }

    /// Fetch `ArtistFacet`s for the assembled artist SELECT — the shared engine for `artists()`
    /// and `artist(id:)`.
    internal static func fetchArtists(
        _ db: Database, extraWhere: String, order: String, limited: Bool, arguments: StatementArguments
    ) throws -> [ArtistFacet] {
        try ArtistFacet.fetchAll(
            db, sql: artistSelectSQL(extraWhere: extraWhere, order: order, limited: limited), arguments: arguments
        )
    }

    // MARK: - Album drill-downs

    /// Albums CREDITED to `artistID` as album-artist (`album_artist_id`), ordered by `sortedBy`
    /// (year by default). The Music.app "Artist → Albums" lens. Uses `idx_albums_artist`.
    func albums(byArtist artistID: Int64, sortedBy sort: FacetSort = .year) async throws -> [AlbumFacet] {
        let order = sort == .year ? LibraryStore.albumYearOrder : LibraryStore.albumTitleOrder
        return try await dbWriter.read { db in
            try Self.fetchAlbums(db, whereClause: "WHERE al.album_artist_id = ?", order: order,
                                 limited: false, arguments: [artistID])
        }
    }

    /// Albums that contain at least one track in genre `genreID`, via a `track_genres` JOIN
    /// inside a DISTINCT sub-select — so an album with several tracks in the genre lists ONCE.
    func albums(inGenre genreID: Int64) async throws -> [AlbumFacet] {
        try await dbWriter.read { db in
            try Self.fetchAlbums(db, whereClause: LibraryStore.albumsInGenreWhere,
                                 order: LibraryStore.albumTitleOrder, limited: false, arguments: [genreID])
        }
    }

    // MARK: - Single-facet detail reads

    /// The single `AlbumFacet` for `albumID`, or `nil`. Byte-identical to the matching
    /// `albums()` entry (same shared builder) — a detail header reads it directly (BR3).
    func album(id albumID: Int64) async throws -> AlbumFacet? {
        try await dbWriter.read { db in
            try Self.fetchAlbums(db, whereClause: "WHERE al.id = ?", order: LibraryStore.albumTitleOrder,
                                 limited: false, arguments: [albumID]).first
        }
    }

    /// The single `ArtistFacet` for `artistID`, or `nil`. Byte-identical to the matching
    /// `artists()` entry; the id-0 sentinel resolves to `nil` (BR3/BR3b).
    func artist(id artistID: Int64) async throws -> ArtistFacet? {
        try await dbWriter.read { db in
            try Self.fetchArtists(db, extraWhere: "AND ar.id = ?", order: LibraryStore.artistNameOrder,
                                  limited: false, arguments: [artistID]).first
        }
    }

    /// The single `GenreFacet` for `genreID`, or `nil`. Same `count(DISTINCT tg.track_id)`
    /// semantics as `genres()`, so a Genre detail header reads it directly (BR3-style).
    func genre(id genreID: Int64) async throws -> GenreFacet? {
        try await dbWriter.read { db in
            try GenreFacet.fetchOne(db, sql: Self.selectGenreByIDSQL, arguments: [genreID])
        }
    }
}
