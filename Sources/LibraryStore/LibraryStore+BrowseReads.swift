// LibraryStore+BrowseReads — the S9.1 browse/search read additions (design §3), GRDB-backed.
//
// NEW entry points projecting a `LibraryTrackDisplay` (title/artist/album names resolved by
// a SQL LEFT JOIN, so a Songs/search row renders "Title · Artist · Album" in ONE query).
// `LibraryTrackDisplay` decodes via `FetchableRecord`. Like every read (design §2a) these
// touch NO filesystem and run under `DatabasePool` concurrent reads.
//
// The batched artwork-path map and the `EXPLAIN QUERY PLAN` diagnostic hook live here too:
// the former keeps the grid's art lookup to one query per page (chunked under the SQLite
// variable limit); the latter lets the headless gate assert the hot reads stay index-driven
// (BR5 — never `SCAN TABLE tracks`).

import Foundation
import GRDB

// MARK: - LibraryTrackDisplay row decoding (FetchableRecord)

extension LibraryTrackDisplay: FetchableRecord {
    /// Decode a row projected as `LibraryStore.displayTrackColumns` (positional). `title` falls
    /// back to the filename `name` when the tag title is NULL/empty; `url` is rebuilt from the
    /// stored string (no FS access). Index 2 (`name`) is used only for that title fallback.
    public init(row: Row) {
        let name: String = row[2] ?? ""
        let tagTitle: String? = row[6]
        let displayTitle: String
        if let tagTitle, !tagTitle.isEmpty {
            displayTitle = tagTitle
        } else {
            displayTitle = name
        }
        self.init(
            id: row[0],
            url: URL(fileURLWithPath: row[1] ?? "", isDirectory: false),
            title: displayTitle,
            artistID: row[5],
            artistName: row[12] ?? "",
            albumID: row[4],
            albumName: row[13],
            format: row[3] ?? "",
            trackNo: row[7],
            durationMs: row[10],
            year: row[9],
            artworkKey: row[11],
            dateAdded: row[14],
            sampleRate: row[15],
            bitDepth: row[16],
            discNo: row[8],
            fileSize: row[17],
            playCount: row[18],
            lastPlayed: row[19],
            albumArtistName: row[20],
            genreName: row[21]
        )
    }
}

public extension LibraryStore {
    // MARK: - Display track column list (single source of truth)

    /// The projected columns for a `LibraryTrackDisplay` row, in the fixed order
    /// `LibraryTrackDisplay.init(row:)` decodes. Table-qualified (`t.`) because every Display
    /// read LEFT JOINs `artists`/`albums`; `artist_name` is `COALESCE`d to '' while `album_name`
    /// stays a true optional (NULL → nil). Indices 0–16 MUST NOT shift; §12.1 APPENDS 17–21.
    internal static let displayTrackColumns =
        "t.id, t.url, t.name, t.format, t.album_id, t.artist_id, t.title, t.track_no, "
            + "t.disc_no, t.year, t.duration_ms, t.artwork_key, "
            + "COALESCE(ar.name, '') AS artist_name, al.title AS album_name, "
            + "t.date_added, t.sample_rate, t.bit_depth, "
            + "t.file_size, t.play_count, t.last_played, aa.name AS album_artist_name, "
            + "(SELECT MIN(g.name) FROM track_genres tg JOIN genres g ON g.id = tg.genre_id "
            + "WHERE tg.track_id = t.id) AS genre_name"

    // MARK: - Shared SQL fragments (identical text drives the read AND its EXPLAIN)

    internal static let displayByArtistWhere = "WHERE t.artist_id = ?"
    internal static let displayInAlbumWhere = "WHERE t.album_id = ?"
    internal static let displayAlbumDiscTrackOrder = "t.album_id ASC, t.disc_no ASC, t.track_no ASC, t.id ASC"
    internal static let displayDiscTrackOrder = "t.disc_no ASC, t.track_no ASC, t.id ASC"
    internal static let displayInGenreJoin = "JOIN track_genres tg ON tg.track_id = t.id"
    internal static let displayInGenreWhere = "WHERE tg.genre_id = ?"

    /// The artist/album/album-artist LEFT JOIN chain every `displayTrackColumns` consumer MUST
    /// carry (keyed off the `tracks` alias `t`). `LibraryStore+Search.search()` interpolates it
    /// too (its FROM starts at `tracks_fts`) so the join text lives in ONE place. The
    /// `al.album_artist_id <> 0` guard suppresses the id-0 sentinel (→ NULL `album_artist_name`).
    internal static let displayArtistAlbumJoins =
        "LEFT JOIN artists ar ON ar.id = t.artist_id "
            + "LEFT JOIN albums al ON al.id = t.album_id "
            + "LEFT JOIN artists aa ON aa.id = al.album_artist_id AND al.album_artist_id <> 0"

    /// The IN-list chunk size for `artworkCachePaths` — well under SQLite's 32766 bound-variable
    /// limit, so a large grid page never overflows it.
    internal static let artworkKeyChunkSize = 500

    /// The batched artwork `content_hash` → `cache_path` read for one chunk. `placeholders` is the
    /// `?,?,…` list for the chunk's keys (bound, never spliced into SQL).
    private static func artworkCachePathsSQL(placeholders: String) -> String {
        "SELECT content_hash, cache_path FROM artwork WHERE content_hash IN (\(placeholders));"
    }

    // MARK: - Display projection SQL builder

    /// Assemble a `LibraryTrackDisplay` SELECT. Kept a pure static builder so the EXPLAIN hook
    /// reproduces the read's SQL byte-for-byte.
    internal static func displayTracksSQL(
        join: String = "", whereClause: String, order: String, limited: Bool
    ) -> String {
        var sql = "SELECT \(displayTrackColumns) FROM tracks t"
        if !join.isEmpty { sql += " " + join }
        sql += " " + displayArtistAlbumJoins
        if !whereClause.isEmpty { sql += " " + whereClause }
        sql += " ORDER BY \(order)"
        if limited { sql += " LIMIT ? OFFSET ?" }
        sql += ";"
        return sql
    }

    // MARK: - Display track reads

    /// All tracks as display rows, ordered by `sortedBy`. Optional `limit`/`offset` paginate;
    /// `limit == nil` is the unbounded default (byte-identical SQL to the unpaginated form).
    func allTracksDisplay(
        sortedBy sort: TrackSort = .name, limit: Int? = nil, offset: Int = 0
    ) async throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            whereClause: "", order: LibraryStore.trackOrder(sort, prefix: "t."), limited: limit != nil
        )
        let args = StatementArguments(LibraryStore.paginationArgs(limit: limit, offset: offset))
        return try await dbWriter.read { db in try LibraryTrackDisplay.fetchAll(db, sql: sql, arguments: args) }
    }

    /// Display rows for album `albumID`, in disc/track order (the album-detail order).
    func tracksDisplay(inAlbum albumID: Int64) async throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            whereClause: LibraryStore.displayInAlbumWhere, order: LibraryStore.displayDiscTrackOrder, limited: false
        )
        return try await dbWriter.read { db in try LibraryTrackDisplay.fetchAll(db, sql: sql, arguments: [albumID]) }
    }

    /// Display rows for the tracks performed by artist `artistID` (track-artist), in
    /// album/disc/track order.
    func tracksDisplay(byArtist artistID: Int64) async throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            whereClause: LibraryStore.displayByArtistWhere, order: LibraryStore.displayAlbumDiscTrackOrder,
            limited: false
        )
        return try await dbWriter.read { db in try LibraryTrackDisplay.fetchAll(db, sql: sql, arguments: [artistID]) }
    }

    /// Display rows for the tracks in genre `genreID`, via a `track_genres` JOIN. The
    /// `track_genres` PK means one match per track (a track in two genres is NOT double-listed).
    func tracksDisplay(inGenre genreID: Int64) async throws -> [LibraryTrackDisplay] {
        let sql = LibraryStore.displayTracksSQL(
            join: LibraryStore.displayInGenreJoin, whereClause: LibraryStore.displayInGenreWhere,
            order: LibraryStore.displayAlbumDiscTrackOrder, limited: false
        )
        return try await dbWriter.read { db in try LibraryTrackDisplay.fetchAll(db, sql: sql, arguments: [genreID]) }
    }

    /// Display rows for an arbitrary set of track ids, as an `id`→row map (S10.2 2c queue
    /// hydration). ONE query per ≤`artworkKeyChunkSize` chunk instead of N per-id round-trips —
    /// so restoring a large queue on launch is a single read, not hundreds of serial suspensions
    /// (QA break-it #4). A missing id is simply ABSENT (never a throw); duplicate ids collapse in
    /// the map, and the caller re-keys by queue order so a queue holding the same track twice
    /// resolves both slots from the one row. Reuses `LibraryTrackDisplay` so a restored queue
    /// carries the SAME metadata (incl. duration) the live queue was built with (QA break-it #5a).
    func tracksDisplay(ids: [Int64]) async throws -> [Int64: LibraryTrackDisplay] {
        guard !ids.isEmpty else { return [:] }
        return try await dbWriter.read { db in
            var result: [Int64: LibraryTrackDisplay] = [:]
            result.reserveCapacity(ids.count)
            var start = ids.startIndex
            while start < ids.endIndex {
                let end = ids.index(
                    start, offsetBy: LibraryStore.artworkKeyChunkSize, limitedBy: ids.endIndex
                ) ?? ids.endIndex
                let chunk = Array(ids[start ..< end])
                let placeholders = databaseQuestionMarks(count: chunk.count)
                let sql = LibraryStore.displayTracksSQL(
                    whereClause: "WHERE t.id IN (\(placeholders))",
                    order: LibraryStore.displayDiscTrackOrder, limited: false
                )
                let rows = try LibraryTrackDisplay.fetchAll(db, sql: sql, arguments: StatementArguments(chunk))
                for row in rows {
                    result[row.id] = row
                }
                start = end
            }
            return result
        }
    }

    // MARK: - Artwork cache-path map (batched, chunked IN-list)

    /// Resolve artwork `content_hash` → `cache_path` for `keys` in one batched map. The IN-list
    /// is CHUNKED (`artworkKeyChunkSize`) so it never exceeds SQLite's variable limit. A key with
    /// no `artwork` row is simply ABSENT (never a throw); duplicate keys collapse.
    func artworkCachePaths(forKeys keys: [String]) async throws -> [String: String] {
        guard !keys.isEmpty else { return [:] }
        return try await dbWriter.read { db in
            var result: [String: String] = [:]
            result.reserveCapacity(keys.count)
            var start = keys.startIndex
            while start < keys.endIndex {
                let end = keys.index(
                    start, offsetBy: LibraryStore.artworkKeyChunkSize, limitedBy: keys.endIndex
                ) ?? keys.endIndex
                let chunk = Array(keys[start ..< end])
                let placeholders = databaseQuestionMarks(count: chunk.count)
                let rows = try Row.fetchAll(
                    db, sql: LibraryStore.artworkCachePathsSQL(placeholders: placeholders),
                    arguments: StatementArguments(chunk)
                )
                for row in rows {
                    if let hash = row[0] as String?, let path = row[1] as String? {
                        result[hash] = path
                    }
                }
                start = end
            }
            return result
        }
    }

    /// Single-key convenience over `artworkCachePaths(forKeys:)`. `nil` when the key has no row.
    func artworkCachePath(forKey key: String) async throws -> String? {
        try await artworkCachePaths(forKeys: [key])[key]
    }

    // MARK: - Pagination + ordering helpers (shared across the read families)

    /// The trailing `LIMIT ? OFFSET ?` clause when paginating, else empty (so the SQL is
    /// byte-identical to the historical unbounded form). With `limit == nil`, `offset` is ignored.
    internal static func paginationClause(limit: Int?) -> String {
        limit == nil ? "" : " LIMIT ? OFFSET ?"
    }

    /// The pagination bind values matching `paginationClause` (empty when unbounded). Both are
    /// CLAMPED to `>= 0`: SQLite reads `LIMIT -1` as UNBOUNDED, so a computed-negative page size
    /// must never silently full-load the library (the scale cliff BR5 guards).
    internal static func paginationArgs(limit: Int?, offset: Int) -> [(any DatabaseValueConvertible)?] {
        guard let limit else { return [] }
        return [Int64(max(0, limit)), Int64(max(0, offset))]
    }

    /// The `TrackSort`s whose ORDER BY runs DESC (used by `singleKeyTrackOrder` to pick a
    /// direction). The multi-term composite orders are handled directly in `trackOrder`.
    private static let descendingTrackSorts: Set<TrackSort> = [
        .titleDesc, .artistNameDesc, .albumTitleDesc, .durationDesc, .dateAddedDescending,
        .formatDesc, .yearDesc, .discNoDesc, .trackNoDesc, .fileSizeDesc, .playCountDesc,
        .lastPlayedDesc, .albumArtistDesc,
    ]

    /// The `ORDER BY` body for a `TrackSort`, column-prefixed (`""` for bare `tracks` reads,
    /// `"t."` for the LEFT-JOINed Display reads). ONE definition site so the two read families
    /// never drift; every order ends in `id` as the final unique tiebreaker.
    internal static func trackOrder(_ sort: TrackSort, prefix: String) -> String {
        switch sort {
        case .name:
            return "\(prefix)name COLLATE NOCASE ASC, \(prefix)id ASC"
        case .album:
            return "\(prefix)album_id IS NULL, \(prefix)album_id ASC, "
                + "\(prefix)disc_no ASC, \(prefix)track_no ASC, \(prefix)id ASC"
        case .artistAlbumTrack:
            return "ar.name COLLATE NOCASE ASC, al.title COLLATE NOCASE ASC, "
                + "\(prefix)disc_no ASC, \(prefix)track_no ASC, \(prefix)id ASC"
        default:
            return singleKeyTrackOrder(sort, prefix: prefix)
        }
    }

    /// The `ORDER BY` body for the single-column asc/desc `TrackSort` pairs. Split out so each
    /// switch stays within the cyclomatic-complexity budget. Direction is chosen once from
    /// `descendingTrackSorts`; every order ends in `id` in the SAME direction.
    private static func singleKeyTrackOrder(_ sort: TrackSort, prefix: String) -> String {
        let dir = descendingTrackSorts.contains(sort) ? "DESC" : "ASC"
        switch sort {
        case .titleAsc, .titleDesc:
            return "COALESCE(NULLIF(\(prefix)title, ''), \(prefix)name) COLLATE NOCASE "
                + "\(dir), \(prefix)id \(dir)"
        case .albumTitleAsc, .albumTitleDesc:
            return "al.title IS NULL, al.title COLLATE NOCASE \(dir), \(prefix)id \(dir)"
        case .artistNameAsc, .artistNameDesc:
            return "ar.name IS NULL, ar.name COLLATE NOCASE \(dir), \(prefix)id \(dir)"
        case .durationAsc, .durationDesc:
            return "\(prefix)duration_ms \(dir), \(prefix)id \(dir)"
        case .dateAddedAsc, .dateAddedDescending:
            return "\(prefix)date_added \(dir), \(prefix)id \(dir)"
        case .formatAsc, .formatDesc:
            return "\(prefix)format COLLATE NOCASE \(dir), \(prefix)id \(dir)"
        case .yearAsc, .yearDesc:
            return "\(prefix)year \(dir), \(prefix)id \(dir)"
        default:
            return catalogTrackOrder(sort, prefix: prefix, dir: dir)
        }
    }

    /// The `ORDER BY` body for the S9.5 §12.1 full-catalog columns' asc/desc pairs — split out
    /// so neither switch exceeds the cyclomatic-complexity budget. `dir` is passed in (resolved
    /// once by `singleKeyTrackOrder`).
    private static func catalogTrackOrder(_ sort: TrackSort, prefix: String, dir: String) -> String {
        switch sort {
        case .discNoAsc, .discNoDesc:
            return "\(prefix)disc_no \(dir), \(prefix)id \(dir)"
        case .trackNoAsc, .trackNoDesc:
            return "\(prefix)track_no \(dir), \(prefix)id \(dir)"
        case .fileSizeAsc, .fileSizeDesc:
            return "\(prefix)file_size \(dir), \(prefix)id \(dir)"
        case .playCountAsc, .playCountDesc:
            return "\(prefix)play_count \(dir), \(prefix)id \(dir)"
        case .lastPlayedAsc, .lastPlayedDesc:
            return "\(prefix)last_played \(dir), \(prefix)id \(dir)"
        case .albumArtistAsc, .albumArtistDesc:
            return "aa.name IS NULL, aa.name COLLATE NOCASE \(dir), \(prefix)id \(dir)"
        default:
            // Unreachable: every other TrackSort is resolved in trackOrder/singleKeyTrackOrder.
            return "\(prefix)id \(dir)"
        }
    }

    // MARK: - Query-plan diagnostic (BR5 — the portable scale tripwire)

    /// A hot read whose `EXPLAIN QUERY PLAN` the headless gate asserts stays index-driven (never
    /// a full `tracks` table scan). A VERIFICATION/DIAGNOSTIC hook (NOT browse-facing API).
    enum HotRead: Sendable {
        case tracksDisplayByArtist
        case tracksDisplayInAlbum
        case tracksDisplayInGenre
        case albumsInGenre
    }

    /// The `EXPLAIN QUERY PLAN` `detail` rows for `read`, EXPLAINing the EXACT SQL the read
    /// prepares (built from the SAME shared fragments, so no drift). Diagnostic hook.
    func explainQueryPlan(for read: HotRead) async throws -> [String] {
        let sql: String
        switch read {
        case .tracksDisplayByArtist:
            sql = LibraryStore.displayTracksSQL(
                whereClause: LibraryStore.displayByArtistWhere,
                order: LibraryStore.displayAlbumDiscTrackOrder, limited: false
            )
        case .tracksDisplayInAlbum:
            sql = LibraryStore.displayTracksSQL(
                whereClause: LibraryStore.displayInAlbumWhere,
                order: LibraryStore.displayDiscTrackOrder, limited: false
            )
        case .tracksDisplayInGenre:
            sql = LibraryStore.displayTracksSQL(
                join: LibraryStore.displayInGenreJoin, whereClause: LibraryStore.displayInGenreWhere,
                order: LibraryStore.displayAlbumDiscTrackOrder, limited: false
            )
        case .albumsInGenre:
            sql = LibraryStore.albumSelectSQL(
                whereClause: LibraryStore.albumsInGenreWhere, order: LibraryStore.albumTitleOrder, limited: false
            )
        }
        return try await dbWriter.read { db in try Self.collectQueryPlan(db, sql) }
    }

    /// The `EXPLAIN QUERY PLAN` `detail` rows for the FULL-LIBRARY `allTracksDisplay(sortedBy:)`
    /// read under `sort` — so the gate can classify each sort as index-driven vs filesort (R3).
    func explainAllTracksDisplayPlan(sortedBy sort: TrackSort) async throws -> [String] {
        let sql = LibraryStore.displayTracksSQL(
            whereClause: "", order: LibraryStore.trackOrder(sort, prefix: "t."), limited: false
        )
        return try await dbWriter.read { db in try Self.collectQueryPlan(db, sql) }
    }

    /// Run `EXPLAIN QUERY PLAN <sql>` and collect the `detail` column (index 3) of each plan
    /// row. The `?` placeholders are bound to NULL (the plan is value-independent). Internal so
    /// `LibraryStore+Search`'s `explainSearchMatchingIDsPlan` reuses the SAME collector.
    internal static func collectQueryPlan(_ db: Database, _ sql: String) throws -> [String] {
        let placeholderCount = sql.filter { $0 == "?" }.count
        let nulls = StatementArguments(Array(repeating: DatabaseValue.null, count: placeholderCount))
        let rows = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql, arguments: nulls)
        return rows.map { ($0[3] as String?) ?? "" }
    }
}
