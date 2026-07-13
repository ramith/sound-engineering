// LibraryStore+DAO — the write side of the DAO (design §4), GRDB-backed.
//
// Single writer by construction: every mutation runs in a `dbWriter.write { db in … }`
// closure, which IS one transaction (GRDB opens IMMEDIATE) — so multi-statement work is
// atomic without a hand-rolled `BEGIN`, and the private `*Locked`-style helpers simply
// take a `Database` and run inside the caller's write closure. Only `Sendable` value
// types cross the boundary; no `Database` handle escapes.
//
// Identity model (design §2): `tracks.id` is the durable reference identity;
// `tracks.url` (UNIQUE) is the mutable scan key. `upsert` keys on `url`
// (`ON CONFLICT(url) DO UPDATE`); `moveTrack` is a DISTINCT id-keyed update that changes
// the url in place, preserving id + references. A URL collision surfaces as a typed
// `URLConflict` (M6), mapped from GRDB's `DatabaseError(SQLITE_CONSTRAINT)`.

import Foundation
import GRDB

// MARK: - LibraryFolder row decoding (FetchableRecord)

extension LibraryFolder: FetchableRecord {
    /// Decode a `folders` row projected as `id, path, …` (only id/path are mapped).
    public init(row: Row) {
        self.init(id: row[0], path: row[1] ?? "")
    }
}

public extension LibraryStore {
    // MARK: - SQL

    /// Resolve a folder id by its normalised path.
    private static let selectFolderIDByPathSQL = "SELECT id FROM folders WHERE path = ?;"
    /// Insert a new ROOT folder (is_root = 1) with its bookmark + `(dev, inode)` identity.
    private static let insertRootFolderSQL =
        "INSERT INTO folders(path, is_root, bookmark, dev, inode) VALUES (?, 1, ?, ?, ?);"
    /// The rowid of an existing ROOT for the same on-disk `(dev, inode)` identity (QS3).
    private static let selectExistingRootIDSQL =
        "SELECT id FROM folders WHERE is_root = 1 AND dev = ? AND inode = ? LIMIT 1;"
    /// Every registered scan root, path-ordered.
    private static let selectRootsSQL =
        "SELECT id, path, parent_id, is_root, bookmark, last_scanned FROM folders "
            + "WHERE is_root = 1 ORDER BY path COLLATE NOCASE ASC, id ASC;"
    /// `max(last_seen_scan)` over `tracks` (the next scan generation is this + 1).
    private static let nextScanGenerationSQL = "SELECT max(last_seen_scan) FROM tracks;"
    /// The `(id, file_size, mtime)` signature probe behind `classify`.
    private static let classifyTrackByURLSQL = "SELECT id, file_size, mtime FROM tracks WHERE url = ?;"
    /// Resolve a track id by its unique url (move-conflict pre-flight + post-upsert id lookup).
    private static let selectTrackIDByURLSQL = "SELECT id FROM tracks WHERE url = ?;"
    /// Whether a row already holds `url` (the new-vs-update discriminator in `upsertOne`).
    private static let selectTrackExistsByURLSQL = "SELECT 1 FROM tracks WHERE url = ?;"
    /// Relocate a track in place (url/folder/relative_path) by its stable id (M6).
    private static let moveTrackSQL =
        "UPDATE tracks SET url = ?, folder_id = ?, relative_path = ? WHERE id = ?;"
    /// Refresh ONLY `last_seen_scan` for the row at `url` (liveness, not content).
    private static let stampLastSeenSQL = "UPDATE tracks SET last_seen_scan = ? WHERE url = ?;"
    /// The ids of tracks directly in a folder (captured before a folder delete).
    private static let selectTrackIDsInFolderSQL = "SELECT id FROM tracks WHERE folder_id = ?;"
    /// Delete a single track row by its stable id.
    private static let deleteTrackByIDSQL = "DELETE FROM tracks WHERE id = ?;"
    /// Delete the `folders` row (`ON DELETE SET NULL` detaches its tracks to loose).
    private static let deleteFolderByIDSQL = "DELETE FROM folders WHERE id = ?;"

    /// Upsert ONE scanned file, keyed on `url` (`ON CONFLICT(url) DO UPDATE`). The conflict SET
    /// fires ONLY when a content field differs (idempotency); `last_seen_scan` is stamped
    /// separately (see `stampLastSeen`). dev + inode are the move-signature — bound on insert AND
    /// set on the conflict UPDATE, but DELIBERATELY absent from the no-bump WHERE predicate.
    private static let upsertTrackSQL = """
    INSERT INTO tracks(
        url, folder_id, relative_path, name, format,
        file_size, mtime, inode, dev, date_added, last_seen_scan)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(url) DO UPDATE SET
        folder_id = excluded.folder_id,
        relative_path = excluded.relative_path,
        name = excluded.name,
        format = excluded.format,
        file_size = excluded.file_size,
        mtime = excluded.mtime,
        inode = excluded.inode,
        dev = excluded.dev,
        last_seen_scan = excluded.last_seen_scan,
        metadata_scanned = 0
    WHERE tracks.file_size <> excluded.file_size
       OR tracks.mtime <> excluded.mtime
       OR tracks.name <> excluded.name
       OR tracks.format <> excluded.format
       OR tracks.relative_path <> excluded.relative_path
       OR tracks.folder_id IS NOT excluded.folder_id;
    """

    /// The folder-scoped orphan DELETE mirroring `deleteSearchRowsForSweep`. `placeholders` is the
    /// `?,?,…` list for the folder ids (bound, never spliced); `last_seen_scan < ?` is the last bind.
    private static func deleteTracksForSweepSQL(placeholders: String) -> String {
        "DELETE FROM tracks WHERE folder_id IN (\(placeholders)) AND last_seen_scan < ?;"
    }

    // MARK: - Scan roots

    /// Register (or return the existing) scan-root folder for `url`. Idempotent two ways:
    /// on the normalised path (`UNIQUE(path)`), AND — when `dev`/`inode` are supplied (the
    /// caller's lstat of the root) — on the on-disk `(dev, inode)` identity (QS3).
    /// `bookmark` is stored but reserved-unused under the Developer-ID posture (§8-D5).
    @discardableResult
    func addRoot(_ url: URL, dev: Int64? = nil, inode: Int64? = nil, bookmark: Data? = nil) async throws -> Int64 {
        let path = PathNormalizer.normalizedString(for: url)
        return try await dbWriter.write { db in
            if let existing = try Int64.fetchOne(db, sql: Self.selectFolderIDByPathSQL, arguments: [path]) {
                return existing
            }
            // Same on-disk directory (by lstat identity) already a root? → idempotent.
            if let dev, let inode, let existing = try Self.existingRootID(db, forDev: dev, inode: inode) {
                return existing
            }
            try db.execute(
                sql: Self.insertRootFolderSQL,
                arguments: [path, bookmark, dev, inode]
            )
            return db.lastInsertedRowID
        }
    }

    /// The rowid of an existing ROOT registered for the same on-disk directory (matched
    /// on the lstat `(dev, inode)` identity), or nil. Roots with a NULL dev/inode never
    /// match (SQL `= NULL` is never true). Underlies `addRoot`'s case-insensitive dedup (QS3).
    internal static func existingRootID(_ db: Database, forDev dev: Int64, inode: Int64) throws -> Int64? {
        try Int64.fetchOne(
            db, sql: selectExistingRootIDSQL,
            arguments: [dev, inode]
        )
    }

    /// Every registered scan root, path-ordered.
    func roots() async throws -> [LibraryFolder] {
        try await dbWriter.read { db in
            try LibraryFolder.fetchAll(db, sql: Self.selectRootsSQL)
        }
    }

    /// Remove a scan root, KEEPING any playlist-referenced tracks as loose.
    ///
    /// Locked semantics (design §8 "Remove folder"): removing a root must not delete a
    /// track a playlist references — those detach to loose (`folder_id`→NULL via
    /// `ON DELETE SET NULL`) and survive; only tracks NO playlist references are deleted.
    /// S10.1 (Gate 1 / SEQ-1): `unreferencedTrackIDs` now filters against `playlist_entries`.
    func removeRoot(id folderID: Int64) async throws {
        try await dbWriter.write { db in
            let detaching = try Self.trackIDs(db, inFolder: folderID)
            try Self.deleteFolderRow(db, folderID)
            let toDelete = try Self.unreferencedTrackIDs(db, among: detaching)
            try self.deleteTrackRows(db, ids: toDelete)
            _ = try self.sweepOrphanFacetsLocked(db) // SF-2: reap facets orphaned by the delete, same txn
        }
    }

    // MARK: - Scan generation + classify

    /// Begin a new scan generation: a monotonically increasing integer stamped onto every
    /// row a scan touches (`last_seen_scan`). Derived as `max(last_seen_scan) + 1` so it
    /// survives restarts without extra state.
    func beginScanGeneration() async throws -> Int64 {
        try await dbWriter.read { db in try Self.nextScanGeneration(db) }
    }

    /// `max(last_seen_scan) + 1` on `db` (1 on an empty table). Shared by `beginScanGeneration`
    /// and the per-batch write paths that need a generation inside their own transaction.
    internal static func nextScanGeneration(_ db: Database) throws -> Int64 {
        try (Int64.fetchOne(db, sql: nextScanGenerationSQL) ?? 0) + 1
    }

    /// Classify `file` against the store from its `(fileSize, mtime)` signature (design §6
    /// M2): no stored row → `.new`; identical signature → `.unchanged`; a differing row →
    /// `.modified`. A pure read — no FS access, no mutation.
    func classify(_ file: ScannedFile) async throws -> TrackDelta {
        try await dbWriter.read { db in try Self.classify(db, file) }
    }

    /// The `Database`-scoped body of `classify`, callable inside a write closure (the
    /// reconcile path probes deltas mid-transaction).
    internal static func classify(_ db: Database, _ file: ScannedFile) throws -> TrackDelta {
        let key = PathNormalizer.normalizedString(for: file.url)
        guard let row = try Row.fetchOne(
            db, sql: Self.classifyTrackByURLSQL, arguments: [key]
        ) else { return .new }
        let id: Int64 = row[0]
        let storedSize: Int64 = row[1]
        let storedMtime: Int64 = row[2]
        if storedSize == file.fileSize, storedMtime == file.mtime {
            return .unchanged(id: id)
        }
        return .modified(id: id)
    }

    // MARK: - Upsert (single writer, one transaction)

    /// Upsert a batch of scanned files into `folderID` (nil = loose), stamping
    /// `last_seen_scan = generation`, in ONE transaction. Keys on `url`
    /// (`ON CONFLICT(url) DO UPDATE`). Returns the rowids in input order.
    ///
    /// IDEMPOTENT (design §6-E): an unchanged row is NOT bumped — the conflict update only
    /// writes when a signature/name/format/folder field actually differs; `last_seen_scan`
    /// is refreshed unconditionally (liveness, not content) so orphan detection stays correct.
    @discardableResult
    func upsert(_ files: [ScannedFile], folderID: Int64?, generation: Int64) async throws -> [Int64] {
        let now = LibraryStore.nowSeconds()
        return try await dbWriter.write { db in
            var ids: [Int64] = []
            ids.reserveCapacity(files.count)
            for file in files {
                try ids.append(self.upsertOne(db, file, folderID: folderID, generation: generation, dateAdded: now))
            }
            return ids
        }
    }

    /// Add a single LOOSE file (folder_id NULL) — the "play a file not in any scan folder"
    /// path (Req 2). Adopting it into a folder later is just an `upsert` on the same url.
    @discardableResult
    func addLooseFile(_ file: ScannedFile) async throws -> Int64 {
        let now = LibraryStore.nowSeconds()
        return try await dbWriter.write { db in
            let generation = try Self.nextScanGeneration(db)
            return try self.upsertOne(db, file, folderID: nil, generation: generation, dateAdded: now)
        }
    }

    // MARK: - moveTrack (M6 — id-preserving, DISTINCT from upsert)

    /// Move a track IN PLACE to `newURL`/`newFolderID`, preserving its stable `id` and every
    /// reference to it. DISTINCT from `upsert` (which keys on url and would create a NEW row,
    /// orphaning references — design §4 M6). Moving onto a url another row holds is a typed
    /// `URLConflict` (a duplicate — normal per Req 5), NOT a silent merge.
    func moveTrack(id trackID: Int64, newURL: URL, newFolderID: Int64?, newRelativePath: String) async throws {
        let key = PathNormalizer.normalizedString(for: newURL)
        try await dbWriter.write { db in
            // Pre-flight the UNIQUE(url) collision so we can surface the occupant id.
            if let occupant = try Int64.fetchOne(db, sql: Self.selectTrackIDByURLSQL, arguments: [key]),
               occupant != trackID {
                throw URLConflict(existingID: occupant)
            }
            do {
                try db.execute(
                    sql: Self.moveTrackSQL,
                    arguments: [key, newFolderID, newRelativePath, trackID]
                )
            } catch let error as DatabaseError where error.resultCode.primaryResultCode == .SQLITE_CONSTRAINT {
                // Belt-and-braces: a racing insert between the pre-flight and the UPDATE would
                // still trip UNIQUE(url); map it to the typed conflict.
                throw URLConflict(existingID: nil)
            }
        }
    }

    // MARK: - Sweep + delete

    /// Sweep orphans: delete tracks in `folderIDs` whose `last_seen_scan` is older than
    /// `generation`. LOOSE tracks (folder NULL) are NEVER swept (the `IN (:folders)` filter
    /// excludes NULL by SQL semantics, FS-4). Returns the number of rows deleted.
    @discardableResult
    func sweepOrphans(inFolders folderIDs: [Int64], olderThan generation: Int64) async throws -> Int {
        guard !folderIDs.isEmpty else { return 0 }
        return try await dbWriter.write { db in
            // Clear the FTS rows for the swept set FIRST — after the tracks DELETE the
            // sub-select would find nothing and the FTS rows would leak (design §4).
            try self.deleteSearchRowsForSweep(db, inFolders: folderIDs, olderThan: generation)
            let placeholders = databaseQuestionMarks(count: folderIDs.count)
            try db.execute(
                sql: Self.deleteTracksForSweepSQL(placeholders: placeholders),
                arguments: StatementArguments(folderIDs + [generation])
            )
            return db.changesCount
        }
    }

    /// Delete a single track by its stable id. FK `ON DELETE CASCADE` on `track_genres`
    /// clears its genre links. A no-op if `id` does not exist. The FTS row (not an FK) is
    /// cleared explicitly; both statements commit atomically in the one write transaction.
    func delete(id trackID: Int64) async throws {
        try await dbWriter.write { db in
            try self.deleteSearchRows(db, ids: [trackID]) // FTS is not an FK — clear its row too
            try db.execute(sql: Self.deleteTrackByIDSQL, arguments: [trackID])
        }
    }

    // MARK: - Private write helpers (all take the caller's `Database`)

    /// Upsert ONE file (inside the caller's write transaction). See `upsert` for the
    /// idempotency contract. `dateAdded` (a real epoch) is written ONLY on the first insert
    /// (out of the conflict SET). `internal` so the move-matching path can fall back to it.
    @discardableResult
    internal func upsertOne(
        _ db: Database, _ file: ScannedFile, folderID: Int64?, generation: Int64, dateAdded: Int64
    ) throws -> Int64 {
        let key = PathNormalizer.normalizedString(for: file.url)
        // Detect a genuine new insert (vs an ON CONFLICT update) so the FTS index is seeded
        // ONLY for new rows — a no-op re-scan must do ZERO FTS writes (design §4).
        let isNewRow = try Int64.fetchOne(db, sql: Self.selectTrackExistsByURLSQL, arguments: [key]) == nil
        try db.execute(
            sql: Self.upsertTrackSQL,
            // dev + inode are the move-signature (M-B): bound on insert AND set on the conflict
            // UPDATE, but DELIBERATELY absent from the no-bump WHERE predicate (which gates on
            // CONTENT — size/mtime/name/format/path/folder — not the move-signature).
            arguments: [
                key, folderID, file.relativePath, file.name, file.format,
                file.fileSize, file.mtime, file.inode, file.dev, dateAdded, generation,
            ]
        )
        // The conflict-update's WHERE means an UNCHANGED row makes no row-change, so
        // last_seen_scan would NOT be refreshed by that path. Stamp it unconditionally (it is
        // liveness, not content) so orphan detection stays correct (idempotency preserved).
        try Self.stampLastSeen(db, url: key, generation: generation)
        let id = try Self.rowID(db, forURL: key)
        // Seed the search index for a brand-new track (findable by filename immediately). On an
        // update we intentionally DON'T sync: `name` is a pure function of `url`, so a same-url
        // update changes no searchable field except via the metadata pass (which re-syncs).
        if isNewRow { try syncSearchRow(db, trackID: id) }
        return id
    }

    /// Refresh ONLY `last_seen_scan` for the row at `url` (no content columns).
    private static func stampLastSeen(_ db: Database, url key: String, generation: Int64) throws {
        try db.execute(sql: stampLastSeenSQL, arguments: [generation, key])
    }

    /// The stable id of the row at `url` (after an upsert, whether it inserted or updated).
    /// Looked up by the unique url rather than `lastInsertedRowID` (unreliable across an
    /// `ON CONFLICT DO UPDATE`).
    internal static func rowID(_ db: Database, forURL key: String) throws -> Int64 {
        guard let id = try Int64.fetchOne(db, sql: selectTrackIDByURLSQL, arguments: [key]) else {
            throw SQLiteError.internalError(message: "upsert: row for url not found after write")
        }
        return id
    }

    /// The ids of tracks directly in `folderID` (captured before a folder delete).
    private static func trackIDs(_ db: Database, inFolder folderID: Int64) throws -> [Int64] {
        try Int64.fetchAll(db, sql: selectTrackIDsInFolderSQL, arguments: [folderID])
    }

    /// Delete the `folders` row. `ON DELETE SET NULL` detaches its tracks to loose (NOT
    /// cascade) so playlist memberships survive; child folders cascade.
    private static func deleteFolderRow(_ db: Database, _ folderID: Int64) throws {
        try db.execute(sql: deleteFolderByIDSQL, arguments: [folderID])
    }

    /// The DISTINCT set of track ids referenced by ANY playlist entry (Gate-1 filter).
    private static let selectReferencedTrackIDsSQL =
        "SELECT DISTINCT track_id FROM playlist_entries;"

    /// From `candidates`, the ids NO playlist entry references (design §5, removeRoot).
    ///
    /// S10.1 closes SEQ-1 Gate 1: a playlist-referenced track is NEVER returned here, so
    /// `removeRoot` leaves it in place (detached to loose via `folder_id → NULL`) instead of
    /// deleting it — its `playlist_entries` and FTS rows survive. The candidate ids stay bound
    /// (fetch-the-referenced-set + filter in Swift), never spliced into SQL — same rule as
    /// `deleteTrackRows`. The referenced set is bounded by total tracks (trivial at library
    /// scale) and backed by `idx_playlist_entries_track`.
    private static func unreferencedTrackIDs(_ db: Database, among candidates: [Int64]) throws -> [Int64] {
        guard !candidates.isEmpty else { return [] }
        let referenced = try Set(Int64.fetchAll(db, sql: selectReferencedTrackIDsSQL))
        return candidates.filter { !referenced.contains($0) }
    }

    /// Delete the given track rows by id (inside the caller's write transaction). One DELETE
    /// per id (GRDB caches the prepared statement) rather than a dynamic `IN(...)`: the id set
    /// is caller-supplied and potentially large, so it must never be spliced into SQL.
    private func deleteTrackRows(_ db: Database, ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try deleteSearchRows(db, ids: ids) // FTS is not an FK — clear their rows too
        for id in ids {
            try db.execute(sql: Self.deleteTrackByIDSQL, arguments: [id])
        }
    }
}
