// LibraryStore+Reads — the read side of the S8.1b DAO (design §4).
//
// Every read here goes through the actor-isolated connection and returns only
// `Sendable` value types. CRITICAL (design §2a): reads make NO filesystem calls and
// assert NO file existence — a `tracks.url` may point at a path that has since been
// deleted / modified / moved while the app was closed or running. A diverged row is
// still fully queryable; reconciliation is a scan's job (S8.2/S8.4), never a read's.
//
// The `tracks` column list + row mapper are centralised (`trackColumns` /
// `mapTrackRow`) so every track-returning query decodes identically — one place to
// keep column order and the read model in lock-step. S9.1 adds a parallel
// `LibraryTrackDisplay` projection (LibraryStore+BrowseReads) ALONGSIDE these reads;
// the `LibraryTrack` reads below keep their signatures (gate callers depend on them).
//
// SF-4 seam: reads currently serialize through the writer actor; if S9 browse jank
// appears during a scan, add a SQLITE_OPEN_READONLY connection here (design §5's
// measured-only escape hatch) — a dedicated read connection on the same WAL file.

import Foundation

public extension LibraryStore {
    // MARK: - Track column list + mapper (single source of truth)

    /// The `tracks` columns, in the fixed order `mapTrackRow` decodes. Every
    /// track-returning SELECT projects exactly this list so decoding never drifts.
    ///
    /// Note: `duration_ms` is projected but not mapped into `LibraryTrack` (its field was removed
    /// in the Periphery pass); it's kept here to preserve the positional decode order.
    internal static let trackColumns =
        "id, url, folder_id, relative_path, name, format, file_size, mtime, inode, dev, "
            + "album_id, artist_id, title, track_no, disc_no, year, duration_ms, artwork_key"

    /// Decode the current row of `statement` (projected as `trackColumns`) into a
    /// `LibraryTrack`. `url` is reconstructed from the stored string with
    /// `URL(fileURLWithPath:)`; no filesystem access, no existence assertion.
    internal func mapTrackRow(_ statement: SQLiteStatement) -> LibraryTrack {
        LibraryTrack(
            id: statement.columnInt64(0),
            url: URL(fileURLWithPath: statement.columnText(1) ?? "", isDirectory: false),
            folderID: statement.columnIsNull(2) ? nil : statement.columnInt64(2),
            relativePath: statement.columnText(3) ?? "",
            name: statement.columnText(4) ?? "",
            format: statement.columnText(5) ?? "",
            fileSize: statement.columnInt64(6),
            mtime: statement.columnInt64(7),
            inode: statement.columnIsNull(8) ? nil : statement.columnInt64(8),
            dev: statement.columnIsNull(9) ? nil : statement.columnInt64(9),
            albumID: statement.columnIsNull(10) ? nil : statement.columnInt64(10),
            artistID: statement.columnIsNull(11) ? nil : statement.columnInt64(11),
            title: statement.columnText(12),
            trackNo: statement.columnIsNull(13) ? nil : statement.columnInt(13),
            discNo: statement.columnIsNull(14) ? nil : statement.columnInt(14),
            year: statement.columnIsNull(15) ? nil : statement.columnInt(15),
            artworkKey: statement.columnText(17)
        )
    }

    /// Run `sql` (projecting `trackColumns`), binding `bind` to it, and map every
    /// row to a `LibraryTrack`. The shared engine for all track list reads.
    internal func fetchTracks(_ sql: String, bind: (SQLiteStatement) throws -> Void = { _ in }) throws
        -> [LibraryTrack] {
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        try bind(statement)
        var tracks: [LibraryTrack] = []
        while try statement.step() {
            tracks.append(mapTrackRow(statement))
        }
        return tracks
    }

    // MARK: - Track reads

    /// All tracks in the store, ordered by `sortedBy`. Optional `limit`/`offset`
    /// paginate; `limit == nil` is the unbounded default (non-breaking — the SQL is
    /// byte-identical to the historical unpaginated form). Reads never touch the FS (§2a).
    func allTracks(sortedBy sort: TrackSort = .name, limit: Int? = nil, offset: Int = 0) throws -> [LibraryTrack] {
        let sql = "SELECT \(LibraryStore.trackColumns) FROM tracks ORDER BY "
            + LibraryStore.trackOrder(sort, prefix: "")
            + LibraryStore.paginationClause(limit: limit) + ";"
        return try fetchTracks(sql) { statement in
            try LibraryStore.bindPagination(statement, limit: limit, offset: offset, firstIndex: 1)
        }
    }

    /// The single track at `url` (its normalised key form), or `nil` if absent.
    func track(url: URL) throws -> LibraryTrack? {
        let key = PathNormalizer.normalizedString(for: url)
        let rows = try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE url = ?;"
        ) { statement in
            try statement.bind(key, at: 1)
        }
        return rows.first
    }

    /// The single track with stable id `id`, or `nil` if absent.
    func track(id: Int64) throws -> LibraryTrack? {
        let rows = try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE id = ?;"
        ) { statement in
            try statement.bind(id, at: 1)
        }
        return rows.first
    }

    /// All tracks directly under folder `folderID`, name-ordered.
    func tracks(inFolder folderID: Int64) throws -> [LibraryTrack] {
        try fetchTracks(
            "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE folder_id = ? "
                + "ORDER BY name COLLATE NOCASE ASC, id ASC;"
        ) { statement in
            try statement.bind(folderID, at: 1)
        }
    }

    /// Total number of track rows in the store.
    func trackCount() throws -> Int {
        try Int(connection.scalarInt("SELECT count(*) FROM tracks;") ?? 0)
    }

    /// Number of track rows directly under `folderID` — the cheap pre-scan magnitude the
    /// empty-walk safety guard uses (S8.4 slice 3): a walk that sees 0 files while this is
    /// > 0 must REFUSE the sweep (an unmounted/zombie volume must never read as mass-deletion).
    func trackCount(inFolder folderID: Int64) throws -> Int {
        let statement = try connection.prepare("SELECT count(*) FROM tracks WHERE folder_id = ?;")
        defer { statement.finalize() }
        try statement.bind(folderID, at: 1)
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt64(0))
    }

    /// Ids of tracks that still need a metadata attempt (`metadata_scanned == 0`),
    /// id-ordered, capped at `limit` — the S8.3 metadata-pass driving query. A no-tags
    /// file, once marked, never reappears here (the anti-loop guarantee); a retagged
    /// file is reset to 0 by the upsert and reappears. FS-independent (§2a).
    func tracksNeedingMetadata(limit: Int) throws -> [Int64] {
        let statement = try connection.prepare(
            "SELECT id FROM tracks WHERE metadata_scanned = 0 ORDER BY id ASC LIMIT ?;"
        )
        defer { statement.finalize() }
        try statement.bind(Int64(limit), at: 1)
        var ids: [Int64] = []
        while try statement.step() {
            ids.append(statement.columnInt64(0))
        }
        return ids
    }
}
