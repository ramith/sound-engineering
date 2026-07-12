// LibraryStore+Reads — the read side of the DAO (design §4), GRDB-backed.
//
// Every read runs in a `dbWriter.read { db in … }` snapshot and returns only
// `Sendable` value types. CRITICAL (design §2a): reads make NO filesystem calls and
// assert NO file existence — a `tracks.url` may point at a path that has since been
// deleted / modified / moved. A diverged row is still fully queryable; reconciliation
// is a scan's job (S8.2/S8.4), never a read's.
//
// `LibraryTrack` decodes via a GRDB `FetchableRecord` `init(row:)` (the former
// `mapTrackRow`), positional against the fixed `trackColumns` list — one place to keep
// column order and the read model in lock-step. `DatabasePool` reads run concurrently
// with the single writer (the old single-connection actor serialized them).

import Foundation
import GRDB

// MARK: - LibraryTrack row decoding (FetchableRecord)

extension LibraryTrack: FetchableRecord {
    /// Decode a row projected as `LibraryStore.trackColumns` (positional). `url` is
    /// reconstructed from the stored string — no filesystem access, no existence assertion.
    /// `duration_ms` (index 16) is projected but unmapped (kept to preserve decode order).
    public init(row: Row) {
        self.init(
            id: row[0],
            url: URL(fileURLWithPath: row[1] ?? "", isDirectory: false),
            folderID: row[2],
            relativePath: row[3] ?? "",
            name: row[4] ?? "",
            format: row[5] ?? "",
            fileSize: row[6],
            mtime: row[7],
            inode: row[8],
            dev: row[9],
            albumID: row[10],
            artistID: row[11],
            title: row[12],
            trackNo: row[13],
            discNo: row[14],
            year: row[15],
            artworkKey: row[17]
        )
    }
}

public extension LibraryStore {
    // MARK: - Track column list (single source of truth)

    /// The `tracks` columns, in the fixed order `LibraryTrack.init(row:)` decodes. Every
    /// track-returning SELECT projects exactly this list so decoding never drifts.
    ///
    /// Note: `duration_ms` is projected but not mapped into `LibraryTrack`; it's kept
    /// here to preserve the positional decode order.
    internal static let trackColumns =
        "id, url, folder_id, relative_path, name, format, file_size, mtime, inode, dev, "
            + "album_id, artist_id, title, track_no, disc_no, year, duration_ms, artwork_key"

    // MARK: - SQL

    /// The single track at a url (its normalised key form).
    private static let selectTrackByURLSQL = "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE url = ?;"
    /// The single track with a stable id.
    private static let selectTrackByIDSQL = "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE id = ?;"
    /// All tracks directly under a folder, name-ordered.
    private static let selectTracksInFolderSQL =
        "SELECT \(LibraryStore.trackColumns) FROM tracks WHERE folder_id = ? "
            + "ORDER BY name COLLATE NOCASE ASC, id ASC;"
    /// Total number of track rows in the store.
    private static let selectTrackCountSQL = "SELECT count(*) FROM tracks;"
    /// Number of track rows directly under a folder (the empty-walk safety magnitude).
    private static let selectTrackCountInFolderSQL = "SELECT count(*) FROM tracks WHERE folder_id = ?;"
    /// Ids of tracks still needing a metadata attempt (`metadata_scanned == 0`), id-ordered, capped.
    private static let selectTracksNeedingMetadataSQL =
        "SELECT id FROM tracks WHERE metadata_scanned = 0 ORDER BY id ASC LIMIT ?;"

    /// Assemble the bare-`tracks` SELECT projecting `trackColumns`, ordered by `order` with the
    /// pagination `clause` appended (empty when unbounded) — the bare-`tracks` list read's SQL in
    /// one named place (mirrors the `displayTracksSQL` builder for the Display reads).
    private static func allTracksSQL(order: String, paginationClause clause: String) -> String {
        "SELECT \(trackColumns) FROM tracks ORDER BY \(order)\(clause);"
    }

    // MARK: - Track reads

    /// All tracks in the store, ordered by `sortedBy`. Optional `limit`/`offset`
    /// paginate; `limit == nil` is the unbounded default (byte-identical SQL to the
    /// historical unpaginated form). Reads never touch the FS (§2a).
    func allTracks(
        sortedBy sort: TrackSort = .name, limit: Int? = nil, offset: Int = 0
    ) async throws -> [LibraryTrack] {
        let sql = LibraryStore.allTracksSQL(
            order: LibraryStore.trackOrder(sort, prefix: ""),
            paginationClause: LibraryStore.paginationClause(limit: limit)
        )
        let args = StatementArguments(LibraryStore.paginationArgs(limit: limit, offset: offset))
        return try await dbWriter.read { db in try LibraryTrack.fetchAll(db, sql: sql, arguments: args) }
    }

    /// The single track at `url` (its normalised key form), or `nil` if absent.
    func track(url: URL) async throws -> LibraryTrack? {
        let key = PathNormalizer.normalizedString(for: url)
        return try await dbWriter.read { db in
            try LibraryTrack.fetchOne(
                db, sql: Self.selectTrackByURLSQL, arguments: [key]
            )
        }
    }

    /// The single track with stable id `id`, or `nil` if absent.
    func track(id: Int64) async throws -> LibraryTrack? {
        try await dbWriter.read { db in
            try LibraryTrack.fetchOne(
                db, sql: Self.selectTrackByIDSQL, arguments: [id]
            )
        }
    }

    /// All tracks directly under folder `folderID`, name-ordered.
    func tracks(inFolder folderID: Int64) async throws -> [LibraryTrack] {
        try await dbWriter.read { db in
            try LibraryTrack.fetchAll(
                db,
                sql: Self.selectTracksInFolderSQL,
                arguments: [folderID]
            )
        }
    }

    /// Total number of track rows in the store.
    func trackCount() async throws -> Int {
        try await dbWriter.read { db in try Int.fetchOne(db, sql: Self.selectTrackCountSQL) ?? 0 }
    }

    /// Number of track rows directly under `folderID` — the cheap pre-scan magnitude the
    /// empty-walk safety guard uses (S8.4 slice 3): a walk that sees 0 files while this is
    /// > 0 must REFUSE the sweep (an unmounted/zombie volume must never read as mass-deletion).
    func trackCount(inFolder folderID: Int64) async throws -> Int {
        try await dbWriter.read { db in
            try Int.fetchOne(db, sql: Self.selectTrackCountInFolderSQL, arguments: [folderID]) ?? 0
        }
    }

    /// Ids of tracks that still need a metadata attempt (`metadata_scanned == 0`),
    /// id-ordered, capped at `limit` — the S8.3 metadata-pass driving query. A no-tags
    /// file, once marked, never reappears here (the anti-loop guarantee); a retagged
    /// file is reset to 0 by the upsert and reappears. FS-independent (§2a).
    func tracksNeedingMetadata(limit: Int) async throws -> [Int64] {
        try await dbWriter.read { db in
            try Int64.fetchAll(
                db, sql: Self.selectTracksNeedingMetadataSQL,
                arguments: [Int64(limit)]
            )
        }
    }
}
