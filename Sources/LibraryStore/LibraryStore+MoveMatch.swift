// LibraryStore+MoveMatch — the id-preserving reconcile write path (S8.4), GRDB-backed.
//
// The three ops that turn a scan/reconcile of a MOVED file into an id-preserving
// relocation rather than delete-old + insert-new (which would mint a new `tracks.id` and
// orphan every reference — the hard gate SEQ-1/Gate-2):
//   • `moveCandidate` — the UNIQUE unswept row whose move-signature matches a newly seen
//     file. Ambiguity / nil signature → no match (a new id is recoverable; a WRONG id is
//     silent corruption).
//   • `moveMatched` / `moveMatchedLocked` — relocate in place AND stamp
//     `last_seen_scan = generation` in one write, so the end-of-walk sweep does not delete
//     the just-moved row (`moveTrack` alone leaves `last_seen_scan` stale).
//   • `upsertReconciling` — the batch write the scanner's walk calls: probe-or-move, else
//     fall back to the url-keyed `upsertOne`, all in ONE per-batch write transaction.

import Foundation
import GRDB

public extension LibraryStore {
    // MARK: - SQL

    /// The UNIQUE unswept move-signature match probe (`LIMIT 2` so >1 ⇒ ambiguous ⇒ no match).
    private static let moveCandidateSQL =
        "SELECT id FROM tracks WHERE dev = ? AND inode = ? AND file_size = ? AND mtime = ? "
            + "AND format = ? AND last_seen_scan < ? AND url <> ? LIMIT 2;"
    /// Pre-flight the UNIQUE(url) collision so the occupant id can be surfaced (M6 idiom).
    /// (Same text as `LibraryStore+DAO`'s `selectTrackIDByURLSQL`, kept file-private per module.)
    private static let selectTrackIDByURLSQL = "SELECT id FROM tracks WHERE url = ?;"
    /// The id-preserving relocation UPDATE (url/folder/path/name/format + move-signature + last-seen).
    private static let moveMatchedSQL = """
    UPDATE tracks SET
        url = ?, folder_id = ?, relative_path = ?, name = ?, format = ?,
        file_size = ?, mtime = ?, inode = ?, dev = ?, last_seen_scan = ?
    WHERE id = ?;
    """

    /// Find the UNIQUE unswept row whose move-signature matches `file` — a candidate for an
    /// id-preserving MOVE — or nil if none / AMBIGUOUS (>1). Seeks `idx_tracks_dev_inode`.
    /// Matches the full `(dev, inode, size, mtime)` signature PLUS `format` (a real
    /// audio→audio move keeps its extension); `name` is DELIBERATELY not matched (a rename
    /// changes the basename). Nil dev/inode → nil; >1 match → nil (a NEW id is recoverable,
    /// a WRONG id is silent corruption).
    func moveCandidate(for file: ScannedFile, generation: Int64) async throws -> Int64? {
        try await dbWriter.read { db in try Self.moveCandidate(db, for: file, generation: generation) }
    }

    /// The `Database`-scoped body of `moveCandidate`, callable inside the reconcile write
    /// closure. Fetches `LIMIT 2` and returns the id only when EXACTLY one row matches.
    internal static func moveCandidate(_ db: Database, for file: ScannedFile, generation: Int64) throws -> Int64? {
        guard let dev = file.dev, let inode = file.inode else { return nil }
        let key = PathNormalizer.normalizedString(for: file.url)
        let ids = try Int64.fetchAll(
            db,
            sql: Self.moveCandidateSQL,
            arguments: [dev, inode, file.fileSize, file.mtime, file.format, generation, key]
        )
        guard ids.count == 1 else { return nil } // zero candidates, or >1 ⇒ ambiguous ⇒ no match
        return ids[0]
    }

    /// Move-match: an id-preserving relocation discovered during a scan/reconcile. In ONE
    /// write it updates url/folder_id/relative_path/name/format, refreshes the move-signature,
    /// AND stamps `last_seen_scan = generation` — so the end-of-walk sweep does NOT then
    /// delete the just-moved row. Preserves the stable `id` (+ references). Throws
    /// `URLConflict` on a url collision. Does NOT touch `metadata_scanned` (a pure move keeps
    /// the same bytes, so tags stay valid).
    func moveMatched(id trackID: Int64, to file: ScannedFile, newFolderID: Int64?, generation: Int64) async throws {
        try await dbWriter.write { db in
            try self.moveMatchedLocked(db, id: trackID, to: file, newFolderID: newFolderID, generation: generation)
        }
    }

    /// Like `upsert`, but per file FIRST attempts an id-preserving MOVE match before falling
    /// back to the url-keyed upsert. ONE write transaction for the whole batch; returns rowids
    /// in input order. A move probe runs ONLY for a genuinely NEW url; ambiguity / nil
    /// signature / url collision all fall back to a plain upsert — every uncertainty resolves
    /// to the safe side (new id, never wrong id).
    @discardableResult
    func upsertReconciling(_ files: [ScannedFile], folderID: Int64?, generation: Int64) async throws -> [Int64] {
        let now = LibraryStore.nowSeconds()
        return try await dbWriter.write { db in
            var ids: [Int64] = []
            ids.reserveCapacity(files.count)
            for file in files {
                if case .new = try Self.classify(db, file), file.inode != nil, file.dev != nil,
                   let candidate = try Self.moveCandidate(db, for: file, generation: generation) {
                    do {
                        try self.moveMatchedLocked(
                            db, id: candidate, to: file, newFolderID: folderID, generation: generation
                        )
                        ids.append(candidate)
                        continue
                    } catch is URLConflict {
                        // Target url already held (a duplicate/race) → fall through to a plain upsert.
                    }
                }
                try ids.append(self.upsertOne(db, file, folderID: folderID, generation: generation, dateAdded: now))
            }
            return ids
        }
    }

    /// The body of `moveMatched` — so `upsertReconciling` can fold it into its per-batch write
    /// transaction. Runs inside the caller's `Database`. See `moveMatched` for the contract.
    private func moveMatchedLocked(
        _ db: Database, id trackID: Int64, to file: ScannedFile, newFolderID: Int64?, generation: Int64
    ) throws {
        let key = PathNormalizer.normalizedString(for: file.url)
        // Pre-flight the UNIQUE(url) collision so we can surface the occupant id (M6 idiom).
        if let occupant = try Int64.fetchOne(db, sql: Self.selectTrackIDByURLSQL, arguments: [key]),
           occupant != trackID {
            throw URLConflict(existingID: occupant)
        }
        do {
            try db.execute(
                sql: Self.moveMatchedSQL,
                arguments: [
                    key, newFolderID, file.relativePath, file.name, file.format,
                    file.fileSize, file.mtime, file.inode, file.dev, generation, trackID,
                ]
            )
        } catch let error as DatabaseError where error.resultCode.primaryResultCode == .SQLITE_CONSTRAINT {
            // Belt-and-braces: a racing insert between the pre-flight and the UPDATE would still
            // trip UNIQUE(url); map it to the typed conflict (mirrors moveTrack).
            throw URLConflict(existingID: nil)
        }
        // The move rewrote `name` (the pre-metadata FTS title) and does NOT reset
        // metadata_scanned, so nothing else re-syncs it — re-index here (a renamed tagless file
        // must become findable by its new name).
        try syncSearchRow(db, trackID: trackID)
    }
}
