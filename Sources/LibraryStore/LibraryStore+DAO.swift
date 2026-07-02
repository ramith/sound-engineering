// LibraryStore+DAO — the write side of the S8.1b DAO (design §4).
//
// Single writer by construction: every mutation runs on the actor-isolated
// connection, and multi-row work is wrapped in one `BEGIN IMMEDIATE … COMMIT`
// (SQLiteConnection.transaction). Only `Sendable` value types cross the boundary.
//
// Identity model (design §2): `tracks.id` is the durable reference identity;
// `tracks.url` (UNIQUE) is the mutable scan key. `upsert` keys on `url`
// (`ON CONFLICT(url) DO UPDATE`); `moveTrack` is a DISTINCT id-keyed update that
// changes the url in place, preserving id + any references. A URL collision surfaces
// as a typed `URLConflict` (M6).
//
// FS-divergence (design §2a): these writes are the reconciliation primitives
// (classify / upsert / moveTrack / sweepOrphans) S8.4 uses to correct a store that
// diverged from the filesystem. None of them asserts file existence.

import Foundation

public extension LibraryStore {
    // MARK: - Scan roots

    /// Register (or return the existing) scan-root folder for `url`. Idempotent on
    /// the normalised path (`UNIQUE(path)`): a repeat call returns the same rowid.
    /// `bookmark` is stored but reserved-unused under the Developer-ID posture (§8-D5).
    @discardableResult
    func addRoot(_ url: URL, bookmark: Data? = nil) throws -> Int64 {
        let path = PathNormalizer.normalizedString(for: url)
        if let existing = try connection.scalarInt("SELECT id FROM folders WHERE path = ?;", bind: path) {
            return existing
        }
        let statement = try connection.prepare(
            "INSERT INTO folders(path, is_root, bookmark) VALUES (?, 1, ?);"
        )
        defer { statement.finalize() }
        try statement.bind(path, at: 1)
        try statement.bind(bookmark, at: 2)
        _ = try statement.step()
        return connection.lastInsertRowID()
    }

    /// Every registered scan root, path-ordered.
    func roots() throws -> [LibraryFolder] {
        let statement = try connection.prepare(
            "SELECT id, path, parent_id, is_root, bookmark, last_scanned FROM folders "
                + "WHERE is_root = 1 ORDER BY path COLLATE NOCASE ASC, id ASC;"
        )
        defer { statement.finalize() }
        var folders: [LibraryFolder] = []
        while try statement.step() {
            folders.append(LibraryFolder(
                id: statement.columnInt64(0),
                path: statement.columnText(1) ?? "",
                parentID: statement.columnIsNull(2) ? nil : statement.columnInt64(2),
                isRoot: statement.columnInt64(3) == 1,
                bookmark: statement.columnBlob(4),
                lastScanned: statement.columnIsNull(5) ? nil : statement.columnInt64(5)
            ))
        }
        return folders
    }

    /// Remove a scan root, KEEPING any playlist-referenced tracks as loose.
    ///
    /// Locked semantics (design §8 "Remove folder"): removing a root must not delete
    /// a track a playlist references — those detach to loose (`folder_id`→NULL) and
    /// survive; only tracks NO playlist references are deleted. Mechanism, structured
    /// so the S10 "in any playlist?" check slots in cleanly:
    ///   1. capture the ids of the tracks directly in the folder (their memberships
    ///      would be at stake);
    ///   2. delete the folder — the `ON DELETE SET NULL` FK detaches those tracks to
    ///      loose (id + any future memberships preserved) rather than cascading;
    ///   3. delete the just-detached tracks that are unreferenced. With no playlist
    ///      table yet, "unreferenced" is ALL of them; when S10 adds `playlist_tracks`,
    ///      `unreferencedTrackIDs` gains the `NOT IN (SELECT track_id FROM
    ///      playlist_tracks)` filter and referenced tracks simply stay loose.
    func removeRoot(id folderID: Int64) throws {
        try connection.transaction {
            let detaching = try trackIDs(inFolder: folderID)
            try deleteFolderRow(folderID)
            let toDelete = unreferencedTrackIDs(among: detaching)
            try deleteTrackRows(ids: toDelete)
        }
    }

    // MARK: - Scan generation + classify

    /// Begin a new scan generation: a monotonically increasing integer stamped onto
    /// every row a scan touches (`last_seen_scan`). Orphan detection is then
    /// `WHERE folder_id IN(:roots) AND last_seen_scan < :generation`. Derived as
    /// `max(last_seen_scan) + 1` so it survives restarts without extra state.
    func beginScanGeneration() throws -> Int64 {
        let maximum = try connection.scalarInt("SELECT max(last_seen_scan) FROM tracks;") ?? 0
        return maximum + 1
    }

    /// Classify `file` against the store from its `(fileSize, mtime)` signature
    /// (design §6 M2): no stored row → `.new`; a stored row with an identical
    /// signature → `.unchanged`; a stored row differing in EITHER field → `.modified`.
    /// A pure read — no FS access, no mutation.
    func classify(_ file: ScannedFile) throws -> TrackDelta {
        let key = PathNormalizer.normalizedString(for: file.url)
        let statement = try connection.prepare(
            "SELECT id, file_size, mtime FROM tracks WHERE url = ?;"
        )
        defer { statement.finalize() }
        try statement.bind(key, at: 1)
        guard try statement.step() else { return .new }
        let id = statement.columnInt64(0)
        let storedSize = statement.columnInt64(1)
        let storedMtime = statement.columnInt64(2)
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
    /// IDEMPOTENT (design §6-E): an unchanged row is NOT bumped — the conflict update
    /// only writes when a signature/name/format/folder field actually differs, so a
    /// re-scan of a steady-state library leaves `mtime` (and every other column)
    /// untouched. `last_seen_scan` is refreshed unconditionally (it is the liveness
    /// stamp, not track content) so orphan detection stays correct across re-scans.
    @discardableResult
    func upsert(_ files: [ScannedFile], folderID: Int64?, generation: Int64) throws -> [Int64] {
        try connection.transaction {
            var ids: [Int64] = []
            ids.reserveCapacity(files.count)
            for file in files {
                try ids.append(upsertOne(file, folderID: folderID, generation: generation))
            }
            return ids
        }
    }

    /// Add a single LOOSE file (folder_id NULL) — the "play a file not in any scan
    /// folder" path (Req 2). A convenience over `upsert([file], folderID: nil, …)`
    /// with its own fresh generation. Adopting a loose file into a folder later is
    /// just an `upsert` on the same url with a `folderID` (`ON CONFLICT DO UPDATE`).
    @discardableResult
    func addLooseFile(_ file: ScannedFile) throws -> Int64 {
        let generation = try beginScanGeneration()
        return try connection.transaction {
            try upsertOne(file, folderID: nil, generation: generation)
        }
    }

    // MARK: - moveTrack (M6 — id-preserving, DISTINCT from upsert)

    /// Move a track IN PLACE to `newURL`/`newFolderID`, preserving its stable `id`
    /// and every reference to it (playlist memberships, future play-counts). This is
    /// DISTINCT from `upsert`: upsert keys on url and would create a NEW row for the
    /// new path, orphaning references — the exact bug the identity model prevents
    /// (design §4 M6). Moving onto a url another row already holds is a typed
    /// `URLConflict` (a duplicate — normal per Req 5), NOT a silent merge.
    func moveTrack(id trackID: Int64, newURL: URL, newFolderID: Int64?) throws {
        let key = PathNormalizer.normalizedString(for: newURL)
        try connection.transaction {
            // Pre-flight the UNIQUE(url) collision so we can surface the occupant id.
            if let occupant = try connection.scalarInt(
                "SELECT id FROM tracks WHERE url = ?;", bind: key
            ), occupant != trackID {
                throw URLConflict(url: key, existingID: occupant)
            }
            let statement = try connection.prepare(
                "UPDATE tracks SET url = ?, folder_id = ?, relative_path = "
                    + "CASE WHEN ? IS NULL THEN '' ELSE relative_path END WHERE id = ?;"
            )
            defer { statement.finalize() }
            try statement.bind(key, at: 1)
            try statement.bind(newFolderID, at: 2)
            try statement.bind(newFolderID, at: 3)
            try statement.bind(trackID, at: 4)
            do {
                _ = try statement.step()
            } catch let error as SQLiteError where error.isConstraintViolation {
                // Belt-and-braces: a racing insert between the pre-flight and the
                // UPDATE would still trip UNIQUE(url); map it to the typed conflict.
                throw URLConflict(url: key, existingID: nil)
            }
        }
    }

    // MARK: - Sweep + delete

    /// Sweep orphans: delete tracks in `folderIDs` whose `last_seen_scan` is older
    /// than `generation` (i.e. a scan of those folders did not re-see them). LOOSE
    /// tracks (folder NULL) are NEVER swept — the `IN (:folders)` filter excludes
    /// NULL by SQL semantics, so a loose track survives a sweep of any root (FS-4).
    /// Returns the number of rows deleted.
    @discardableResult
    func sweepOrphans(inFolders folderIDs: [Int64], olderThan generation: Int64) throws -> Int {
        guard !folderIDs.isEmpty else { return 0 }
        return try connection.transaction {
            let placeholders = folderIDs.map { _ in "?" }.joined(separator: ", ")
            let statement = try connection.prepare(
                "DELETE FROM tracks WHERE folder_id IN (\(placeholders)) AND last_seen_scan < ?;"
            )
            defer { statement.finalize() }
            var index: Int32 = 1
            for folderID in folderIDs {
                try statement.bind(folderID, at: index)
                index += 1
            }
            try statement.bind(generation, at: index)
            _ = try statement.step()
            return connection.changes()
        }
    }

    /// Delete a single track by its stable id. FK `ON DELETE CASCADE` on
    /// `track_genres` clears its genre links; playlist memberships (S10) will cascade
    /// likewise. A no-op if `id` does not exist.
    func delete(id trackID: Int64) throws {
        let statement = try connection.prepare("DELETE FROM tracks WHERE id = ?;")
        defer { statement.finalize() }
        try statement.bind(trackID, at: 1)
        _ = try statement.step()
    }

    // MARK: - Private write helpers

    /// Upsert ONE file (inside the caller's transaction). See `upsert` for the
    /// idempotency contract. `folderID` nil → loose. On a url collision the
    /// `ON CONFLICT(url) DO UPDATE` refreshes the row in place.
    @discardableResult
    private func upsertOne(_ file: ScannedFile, folderID: Int64?, generation: Int64) throws -> Int64 {
        let key = PathNormalizer.normalizedString(for: file.url)
        let statement = try connection.prepare(
            """
            INSERT INTO tracks(
                url, folder_id, relative_path, name, format,
                file_size, mtime, inode, date_added, last_seen_scan)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path,
                name = excluded.name,
                format = excluded.format,
                file_size = excluded.file_size,
                mtime = excluded.mtime,
                inode = excluded.inode,
                last_seen_scan = excluded.last_seen_scan
            WHERE tracks.file_size <> excluded.file_size
               OR tracks.mtime <> excluded.mtime
               OR tracks.name <> excluded.name
               OR tracks.format <> excluded.format
               OR tracks.relative_path <> excluded.relative_path
               OR tracks.folder_id IS NOT excluded.folder_id;
            """
        )
        defer { statement.finalize() }
        try statement.bind(key, at: 1)
        try statement.bind(folderID, at: 2)
        try statement.bind(file.relativePath, at: 3)
        try statement.bind(file.name, at: 4)
        try statement.bind(file.format, at: 5)
        try statement.bind(file.fileSize, at: 6)
        try statement.bind(file.mtime, at: 7)
        try statement.bind(file.inode, at: 8)
        try statement.bind(generation, at: 9) // date_added (first insert only)
        try statement.bind(generation, at: 10) // last_seen_scan
        _ = try statement.step()

        // The conflict-update's WHERE means an UNCHANGED row makes no row-change, so
        // last_seen_scan would NOT be refreshed by that path. Stamp it unconditionally
        // (it is liveness, not content) so orphan detection stays correct — without
        // bumping any content column (idempotency preserved).
        try stampLastSeen(url: key, generation: generation)
        return try rowID(forURL: key)
    }

    /// Refresh ONLY `last_seen_scan` for the row at `url` (no content columns).
    private func stampLastSeen(url key: String, generation: Int64) throws {
        let statement = try connection.prepare("UPDATE tracks SET last_seen_scan = ? WHERE url = ?;")
        defer { statement.finalize() }
        try statement.bind(generation, at: 1)
        try statement.bind(key, at: 2)
        _ = try statement.step()
    }

    /// The stable id of the row at `url` (after an upsert, whether it inserted or
    /// updated). Looked up by the unique url rather than `last_insert_rowid` (which
    /// is unreliable across an `ON CONFLICT DO UPDATE`).
    private func rowID(forURL key: String) throws -> Int64 {
        guard let id = try connection.scalarInt("SELECT id FROM tracks WHERE url = ?;", bind: key) else {
            throw SQLiteError.internalError(message: "upsert: row for url not found after write")
        }
        return id
    }

    /// The ids of tracks directly in `folderID` (captured before a folder delete so
    /// the detach-then-prune in `removeRoot` knows exactly which rows to consider).
    private func trackIDs(inFolder folderID: Int64) throws -> [Int64] {
        let statement = try connection.prepare("SELECT id FROM tracks WHERE folder_id = ?;")
        defer { statement.finalize() }
        try statement.bind(folderID, at: 1)
        var ids: [Int64] = []
        while try statement.step() {
            ids.append(statement.columnInt64(0))
        }
        return ids
    }

    /// Delete the `folders` row. `ON DELETE SET NULL` detaches its tracks to loose
    /// (NOT cascade) so playlist memberships survive; child folders cascade.
    private func deleteFolderRow(_ folderID: Int64) throws {
        let statement = try connection.prepare("DELETE FROM folders WHERE id = ?;")
        defer { statement.finalize() }
        try statement.bind(folderID, at: 1)
        _ = try statement.step()
    }

    /// From `candidates`, the ids no playlist references (design §8 removeRoot). With
    /// the playlist table deferred (M7) that is ALL of them; the S10 filter slots in
    /// here as `... AND id NOT IN (SELECT track_id FROM playlist_tracks)`. A dedicated
    /// hook (not inlined) so the "in any playlist?" predicate is a one-line change.
    private func unreferencedTrackIDs(among candidates: [Int64]) -> [Int64] {
        candidates
    }

    /// Delete the given track rows by id (inside the caller's transaction).
    private func deleteTrackRows(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        let statement = try connection.prepare("DELETE FROM tracks WHERE id = ?;")
        defer { statement.finalize() }
        for id in ids {
            statement.reset()
            statement.clearBindings()
            try statement.bind(id, at: 1)
            _ = try statement.step()
        }
    }
}
