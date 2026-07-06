// LibraryStore+BrowseReads — the S9.1 browse/search read additions (design §3).
//
// These reads sit ALONGSIDE the existing `LibraryTrack` reads (LibraryStore+Reads):
// they are NEW entry points that project a `LibraryTrackDisplay` (title/artist/album
// names resolved by a SQL LEFT JOIN, so a Songs/search row renders "Title · Artist ·
// Album" in ONE query instead of N per-row lookups). The existing `LibraryTrack`
// reads keep their signatures untouched (gate callers at ChecksFSDivergence.swift:58
// and ChecksConcurrency.swift:367 must keep compiling) — this is additive.
//
// Like every read (design §2a) these touch NO filesystem, assert no existence, and
// run FULLY synchronously per the actor invariant (no `await` between two connection
// calls; the connection never escapes). Values crossing the boundary are `Sendable`.
//
// The batched artwork-path map and the `EXPLAIN QUERY PLAN` diagnostic hook live here
// too: the former keeps the grid's art lookup to one query per page (chunked under the
// SQLite variable limit); the latter lets the headless gate assert the hot reads stay
// index-driven (BR5 — never `SCAN TABLE tracks`), the portable scale tripwire.

import Foundation

public extension LibraryStore {
    // MARK: - Display track column list + mapper (single source of truth)

    /// The projected columns for a `LibraryTrackDisplay` row, in the fixed order
    /// `mapDisplayRow` decodes. Table-qualified (`t.`) because every Display read
    /// LEFT JOINs `artists`/`albums`; `artist_name` is `COALESCE`d to '' (a track with
    /// no artist still yields exactly one row with an empty name), while `album_name`
    /// stays a true optional (NULL → nil) so "no album" is distinguishable.
    ///
    /// Note: a few columns (name, disc_no, year, artwork_key) are projected but not currently
    /// mapped — the matching `LibraryTrackDisplay` fields were removed in the Periphery dead-code
    /// pass. They stay in the SELECT so the positional decode indices don't shift; S9.5's
    /// Songs/detail views re-add the struct fields + their mapper lines (DB schema untouched).
    internal static let displayTrackColumns =
        "t.id, t.url, t.name, t.format, t.album_id, t.artist_id, t.title, t.track_no, "
            + "t.disc_no, t.year, t.duration_ms, t.artwork_key, "
            + "COALESCE(ar.name, '') AS artist_name, al.title AS album_name"

    // MARK: - Shared SQL fragments (identical text drives the read AND its EXPLAIN)

    internal static let displayByArtistWhere = "WHERE t.artist_id = ?"
    internal static let displayInAlbumWhere = "WHERE t.album_id = ?"
    /// Album → disc → track ordering for a multi-album track list (byArtist / inGenre).
    internal static let displayAlbumDiscTrackOrder =
        "t.album_id ASC, t.disc_no ASC, t.track_no ASC, t.id ASC"
    /// Disc → track ordering for a single album's tracks (inAlbum).
    internal static let displayDiscTrackOrder = "t.disc_no ASC, t.track_no ASC, t.id ASC"
    /// The `track_genres` JOIN + WHERE selecting a genre's tracks (shared so the read
    /// and its EXPLAIN reproduce identical SQL). The `track_genres` PK means one match
    /// per track — a 2-genre track is not double-listed within one genre.
    internal static let displayInGenreJoin = "JOIN track_genres tg ON tg.track_id = t.id"
    internal static let displayInGenreWhere = "WHERE tg.genre_id = ?"

    /// The IN-list chunk size for `artworkCachePaths` — a few hundred, well under
    /// SQLite's 32766 bound-variable limit, so a large grid page never overflows it.
    internal static let artworkKeyChunkSize = 500

    // MARK: - Display projection SQL + row mapper

    /// Assemble a `LibraryTrackDisplay` SELECT: `tracks t` (+ an optional extra `join`,
    /// e.g. `track_genres`) LEFT-JOINed to `artists`/`albums`, filtered by `whereClause`,
    /// ordered by `order`, optionally paginated. Kept a pure static builder so the
    /// EXPLAIN hook can reproduce the read's SQL byte-for-byte.
    internal static func displayTracksSQL(
        join: String = "", whereClause: String, order: String, limited: Bool
    ) -> String {
        var sql = "SELECT \(displayTrackColumns) FROM tracks t"
        if !join.isEmpty { sql += " " + join }
        sql += " LEFT JOIN artists ar ON ar.id = t.artist_id"
        sql += " LEFT JOIN albums al ON al.id = t.album_id"
        if !whereClause.isEmpty { sql += " " + whereClause }
        sql += " ORDER BY \(order)"
        if limited { sql += " LIMIT ? OFFSET ?" }
        sql += ";"
        return sql
    }

    /// Decode the current row (projected as `displayTrackColumns`) into a
    /// `LibraryTrackDisplay`. `title` falls back to the filename `name` when the tag
    /// title is NULL or empty; `url` is rebuilt from the stored string (no FS access).
    internal func mapDisplayRow(_ statement: SQLiteStatement) -> LibraryTrackDisplay {
        let name = statement.columnText(2) ?? ""
        let tagTitle = statement.columnText(6)
        let displayTitle: String
        if let tagTitle, !tagTitle.isEmpty {
            displayTitle = tagTitle
        } else {
            displayTitle = name
        }
        return LibraryTrackDisplay(
            id: statement.columnInt64(0),
            url: URL(fileURLWithPath: statement.columnText(1) ?? "", isDirectory: false),
            title: displayTitle,
            artistID: statement.columnIsNull(5) ? nil : statement.columnInt64(5),
            artistName: statement.columnText(12) ?? "",
            albumID: statement.columnIsNull(4) ? nil : statement.columnInt64(4),
            albumName: statement.columnText(13),
            format: statement.columnText(3) ?? "",
            trackNo: statement.columnIsNull(7) ? nil : statement.columnInt(7),
            durationMs: statement.columnInt64(10)
        )
    }

    /// Prepare `sql`, bind `bind`, and map every row to a `LibraryTrackDisplay` — the
    /// shared engine for all Display list reads (mirrors `fetchTracks`).
    internal func fetchDisplayTracks(
        _ sql: String, bind: (SQLiteStatement) throws -> Void = { _ in }
    ) throws -> [LibraryTrackDisplay] {
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        try bind(statement)
        var rows: [LibraryTrackDisplay] = []
        while try statement.step() {
            rows.append(mapDisplayRow(statement))
        }
        return rows
    }

    // MARK: - Display track reads (NEW — alongside the LibraryTrack reads)

    /// All tracks as display rows, ordered by `sortedBy`. Optional `limit`/`offset`
    /// paginate; `limit == nil` is the unbounded default (non-breaking, byte-identical
    /// SQL to the unpaginated form).
    func allTracksDisplay(
        sortedBy sort: TrackSort = .name, limit: Int? = nil, offset: Int = 0
    ) throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            whereClause: "", order: LibraryStore.trackOrder(sort, prefix: "t."), limited: limit != nil
        )
        return try fetchDisplayTracks(sql) { statement in
            try LibraryStore.bindPagination(statement, limit: limit, offset: offset, firstIndex: 1)
        }
    }

    /// Display rows for album `albumID`, in disc/track order (the album-detail order).
    func tracksDisplay(inAlbum albumID: Int64) throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            whereClause: LibraryStore.displayInAlbumWhere,
            order: LibraryStore.displayDiscTrackOrder, limited: false
        )
        return try fetchDisplayTracks(sql) { try $0.bind(albumID, at: 1) }
    }

    /// Display rows for the tracks performed by artist `artistID` (track-artist), in
    /// album/disc/track order.
    func tracksDisplay(byArtist artistID: Int64) throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            whereClause: LibraryStore.displayByArtistWhere,
            order: LibraryStore.displayAlbumDiscTrackOrder, limited: false
        )
        return try fetchDisplayTracks(sql) { try $0.bind(artistID, at: 1) }
    }

    /// Display rows for the tracks in genre `genreID`, via a `track_genres` JOIN. The
    /// `track_genres` PK `(track_id, genre_id)` means one match per track, so a track
    /// in two genres is NOT double-listed within a single genre (no fan-out).
    func tracksDisplay(inGenre genreID: Int64) throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            join: LibraryStore.displayInGenreJoin, whereClause: LibraryStore.displayInGenreWhere,
            order: LibraryStore.displayAlbumDiscTrackOrder, limited: false
        )
        return try fetchDisplayTracks(sql) { try $0.bind(genreID, at: 1) }
    }

    // MARK: - Artwork cache-path map (batched, chunked IN-list)

    /// Resolve artwork `content_hash` → `cache_path` for `keys` in one batched map.
    /// The IN-list is CHUNKED (`artworkKeyChunkSize`) so it never exceeds SQLite's
    /// variable limit (32766) on a large grid page. A key with no `artwork` row is
    /// simply ABSENT from the result (never a throw); duplicate keys collapse.
    func artworkCachePaths(forKeys keys: [String]) throws -> [String: String] {
        guard !keys.isEmpty else { return [:] }
        var result: [String: String] = [:]
        result.reserveCapacity(keys.count)
        var start = keys.startIndex
        while start < keys.endIndex {
            let end = keys.index(
                start, offsetBy: LibraryStore.artworkKeyChunkSize, limitedBy: keys.endIndex
            ) ?? keys.endIndex
            try fetchArtworkChunk(Array(keys[start ..< end]), into: &result)
            start = end
        }
        return result
    }

    /// Single-key convenience over `artworkCachePaths(forKeys:)`. `nil` when the key
    /// has no artwork row.
    func artworkCachePath(forKey key: String) throws -> String? {
        try artworkCachePaths(forKeys: [key])[key]
    }

    /// SELECT `content_hash, cache_path` for one chunk of keys and merge into `result`.
    /// Placeholders are structural (count-driven); every value is bound (no injection).
    private func fetchArtworkChunk(_ chunk: [String], into result: inout [String: String]) throws {
        let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
        let statement = try connection.prepare(
            "SELECT content_hash, cache_path FROM artwork WHERE content_hash IN (\(placeholders));"
        )
        defer { statement.finalize() }
        for (offset, key) in chunk.enumerated() {
            try statement.bind(key, at: Int32(offset + 1))
        }
        while try statement.step() {
            if let hash = statement.columnText(0), let path = statement.columnText(1) {
                result[hash] = path
            }
        }
    }

    // MARK: - Pagination + ordering helpers (shared across the read families)

    /// The trailing `LIMIT ? OFFSET ?` clause when paginating, else empty. Empty means
    /// the SQL is byte-identical to the historical unbounded form (non-breaking). With
    /// `limit == nil` there is no clause, so `offset` is IGNORED (nil = unbounded).
    internal static func paginationClause(limit: Int?) -> String {
        limit == nil ? "" : " LIMIT ? OFFSET ?"
    }

    /// Bind the pagination `limit`/`offset` at `firstIndex`/`firstIndex+1` when
    /// `limit` is non-nil (matching `paginationClause`); a no-op otherwise. Both are
    /// CLAMPED to `>= 0`: SQLite reads `LIMIT -1` as UNBOUNDED, so a computed-negative
    /// page size must never silently full-load the library (the scale cliff BR5 guards).
    internal static func bindPagination(
        _ statement: SQLiteStatement, limit: Int?, offset: Int, firstIndex: Int32
    ) throws {
        guard let limit else { return }
        try statement.bind(Int64(max(0, limit)), at: firstIndex)
        try statement.bind(Int64(max(0, offset)), at: firstIndex + 1)
    }

    /// The `ORDER BY` body for a `TrackSort`, column-prefixed (`""` for the bare
    /// `tracks` reads, `"t."` for the LEFT-JOINed Display reads). One definition so the
    /// two read families can never drift in ordering.
    internal static func trackOrder(_ sort: TrackSort, prefix: String) -> String {
        switch sort {
        case .name:
            return "\(prefix)name COLLATE NOCASE ASC, \(prefix)id ASC"
        case .album:
            return "\(prefix)album_id IS NULL, \(prefix)album_id ASC, "
                + "\(prefix)disc_no ASC, \(prefix)track_no ASC, \(prefix)id ASC"
        case .dateAddedDescending:
            return "\(prefix)date_added DESC, \(prefix)id DESC"
        }
    }

    // MARK: - Query-plan diagnostic (BR5 — the portable scale tripwire)

    /// A hot read whose `EXPLAIN QUERY PLAN` the headless gate asserts stays
    /// index-driven (never a full `tracks` table scan). A VERIFICATION/DIAGNOSTIC hook
    /// (NOT browse-facing API) — like the `countRows`/`setUserState` hooks, it exists so
    /// the harness can prove the scale invariant against the shipped SQL.
    enum HotRead: Sendable {
        case tracksDisplayByArtist
        case tracksDisplayInAlbum
        case tracksDisplayInGenre
        case albumsInYear
        case albumsInGenre
    }

    /// The `EXPLAIN QUERY PLAN` `detail` rows for `read`, EXPLAINing the EXACT SQL the
    /// corresponding read prepares (built from the SAME shared fragments, so no drift).
    /// The plan is independent of bound values, so the placeholders are left unbound.
    /// Diagnostic/verification hook (see `HotRead`), not browse-facing.
    func explainQueryPlan(for read: HotRead) throws -> [String] {
        switch read {
        case .tracksDisplayByArtist:
            return try collectQueryPlan(LibraryStore.displayTracksSQL(
                whereClause: LibraryStore.displayByArtistWhere,
                order: LibraryStore.displayAlbumDiscTrackOrder, limited: false
            ))
        case .tracksDisplayInAlbum:
            return try collectQueryPlan(LibraryStore.displayTracksSQL(
                whereClause: LibraryStore.displayInAlbumWhere,
                order: LibraryStore.displayDiscTrackOrder, limited: false
            ))
        case .tracksDisplayInGenre:
            return try collectQueryPlan(LibraryStore.displayTracksSQL(
                join: LibraryStore.displayInGenreJoin, whereClause: LibraryStore.displayInGenreWhere,
                order: LibraryStore.displayAlbumDiscTrackOrder, limited: false
            ))
        case .albumsInYear:
            return try collectQueryPlan(LibraryStore.albumSelectSQL(
                whereClause: LibraryStore.albumsInYearWhere,
                order: LibraryStore.albumTitleOrder, limited: false
            ))
        case .albumsInGenre:
            return try collectQueryPlan(LibraryStore.albumSelectSQL(
                whereClause: LibraryStore.albumsInGenreWhere,
                order: LibraryStore.albumTitleOrder, limited: false
            ))
        }
    }

    /// Run `EXPLAIN QUERY PLAN <sql>` and collect the `detail` column (index 3) of each
    /// plan row.
    private func collectQueryPlan(_ sql: String) throws -> [String] {
        let statement = try connection.prepare("EXPLAIN QUERY PLAN " + sql)
        defer { statement.finalize() }
        var details: [String] = []
        while try statement.step() {
            details.append(statement.columnText(3) ?? "")
        }
        return details
    }
}
