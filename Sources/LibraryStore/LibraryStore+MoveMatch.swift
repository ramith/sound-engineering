// LibraryStore+MoveMatch — the S8.4 id-preserving reconcile write path.
//
// Split out of LibraryStore+DAO (file-length) and cohesive on its own: the three ops that
// turn a scan/reconcile of a MOVED file into an id-preserving relocation rather than
// delete-old + insert-new (which would mint a new `tracks.id` and orphan every future
// reference — the hard gate SEQ-1/Gate-2 blocking S9/S10).
//
// The pieces, and why each exists:
//   • `moveCandidate` — finds the UNIQUE unswept row whose move-signature matches a newly
//     seen file. Safe by construction: ambiguity / nil signature → no match (a new id is
//     recoverable; a WRONG id is silent corruption).
//   • `moveMatched` / `moveMatchedLocked` — relocate in place AND stamp
//     `last_seen_scan = generation` in one transaction. The stamp is the crux: `moveTrack`
//     (LibraryStore+DAO) does NOT touch `last_seen_scan`, so without it the just-moved row
//     would still be `< generation` and the end-of-walk sweep would delete it.
//   • `upsertReconciling` — the batch write the scanner's walk calls: probe-or-move, else
//     fall back to the url-keyed `upsertOne`, all in ONE per-batch transaction.

import Foundation

public extension LibraryStore {
    /// Find the UNIQUE unswept row whose move-signature matches `file` — a candidate for
    /// an id-preserving MOVE discovered during a reconcile — or nil if there is none or
    /// the match is AMBIGUOUS (>1). Seeks `idx_tracks_dev_inode`. Scoped to rows this scan
    /// has NOT yet re-seen (`last_seen_scan < generation`) — plausible vacated old
    /// locations — and excludes the file's own url. Matches the full `(dev, inode, size,
    /// mtime)` signature PLUS `format` (safe corroboration: a real audio→audio move keeps
    /// its extension, so it never breaks a legitimate match, yet it blocks an inode reused
    /// by a different-format file). `name` is DELIBERATELY not matched — a rename changes
    /// the basename, so requiring it would break rename detection. A nil dev/inode → nil
    /// (an unreadable signature must never risk an id reassignment; `(size,mtime)` alone is
    /// too weak). >1 match → nil: a NEW id is recoverable, a WRONG id is silent corruption.
    func moveCandidate(for file: ScannedFile, generation: Int64) throws -> Int64? {
        guard let dev = file.dev, let inode = file.inode else { return nil }
        let key = PathNormalizer.normalizedString(for: file.url)
        let statement = try connection.prepare(
            "SELECT id FROM tracks WHERE dev = ? AND inode = ? AND file_size = ? AND mtime = ? "
                + "AND format = ? AND last_seen_scan < ? AND url <> ? LIMIT 2;"
        )
        defer { statement.finalize() }
        try statement.bind(dev, at: 1)
        try statement.bind(inode, at: 2)
        try statement.bind(file.fileSize, at: 3)
        try statement.bind(file.mtime, at: 4)
        try statement.bind(file.format, at: 5)
        try statement.bind(generation, at: 6)
        try statement.bind(key, at: 7)
        guard try statement.step() else { return nil } // zero candidates
        let candidate = statement.columnInt64(0)
        guard try !statement.step() else { return nil } // a second row ⇒ ambiguous ⇒ no match
        return candidate
    }

    /// Move-match: an id-preserving relocation discovered during a scan/reconcile. In ONE
    /// transaction it updates url/folder_id/relative_path/name/format, refreshes the
    /// move-signature (file_size/mtime/inode/dev), AND stamps `last_seen_scan = generation`
    /// — so the end-of-walk sweep does NOT then delete the just-moved row (`moveTrack`
    /// alone leaves `last_seen_scan` stale, which the sweep would reap: the whole S8.4
    /// point). Preserves the stable `id` (+ every reference to it). Throws `URLConflict` on
    /// a url collision (same rule as `moveTrack`). Does NOT touch `metadata_scanned` — a
    /// pure move keeps the same bytes, so tags stay valid (no needless re-extraction).
    func moveMatched(id trackID: Int64, to file: ScannedFile, newFolderID: Int64?, generation: Int64) throws {
        try connection.transaction {
            try moveMatchedLocked(id: trackID, to: file, newFolderID: newFolderID, generation: generation)
        }
    }

    /// Like `upsert`, but per file FIRST attempts an id-preserving MOVE match
    /// (`moveCandidate` → `moveMatchedLocked`) before falling back to the url-keyed upsert.
    /// ONE transaction for the whole batch; returns rowids in input order (the moved row's
    /// stable id, or the upserted id). This is the S8.4 reconcile write path the scanner's
    /// walk uses, so BOTH on-demand re-scans and (later) live reconciles preserve
    /// `tracks.id` across a move. A move probe runs ONLY for a genuinely NEW url (a file at
    /// its known url is not a move); ambiguity / nil signature / url collision all fall back
    /// to a plain upsert — every uncertainty resolves to the safe side (new id, never wrong id).
    @discardableResult
    func upsertReconciling(_ files: [ScannedFile], folderID: Int64?, generation: Int64) throws -> [Int64] {
        let now = LibraryStore.nowSeconds()
        return try connection.transaction {
            var ids: [Int64] = []
            ids.reserveCapacity(files.count)
            for file in files {
                if case .new = try classify(file), file.inode != nil, file.dev != nil,
                   let candidate = try moveCandidate(for: file, generation: generation) {
                    do {
                        try moveMatchedLocked(
                            id: candidate, to: file, newFolderID: folderID, generation: generation
                        )
                        ids.append(candidate)
                        continue
                    } catch is URLConflict {
                        // Target url already held (a duplicate/race) → fall through to a plain upsert.
                    }
                }
                try ids.append(upsertOne(file, folderID: folderID, generation: generation, dateAdded: now))
            }
            return ids
        }
    }

    /// The transaction-free body of `moveMatched` — so `upsertReconciling` can fold it into
    /// its per-batch transaction (SQLite won't nest `BEGIN`). Runs inside the caller's
    /// transaction. See `moveMatched` for the contract.
    private func moveMatchedLocked(
        id trackID: Int64, to file: ScannedFile, newFolderID: Int64?, generation: Int64
    ) throws {
        let key = PathNormalizer.normalizedString(for: file.url)
        // Pre-flight the UNIQUE(url) collision so we can surface the occupant id (M6 idiom).
        if let occupant = try connection.scalarInt(
            "SELECT id FROM tracks WHERE url = ?;", bind: key
        ), occupant != trackID {
            throw URLConflict(url: key, existingID: occupant)
        }
        let statement = try connection.prepare(
            """
            UPDATE tracks SET
                url = ?, folder_id = ?, relative_path = ?, name = ?, format = ?,
                file_size = ?, mtime = ?, inode = ?, dev = ?, last_seen_scan = ?
            WHERE id = ?;
            """
        )
        defer { statement.finalize() }
        try statement.bind(key, at: 1)
        try statement.bind(newFolderID, at: 2)
        try statement.bind(file.relativePath, at: 3)
        try statement.bind(file.name, at: 4)
        try statement.bind(file.format, at: 5)
        try statement.bind(file.fileSize, at: 6)
        try statement.bind(file.mtime, at: 7)
        try statement.bind(file.inode, at: 8)
        try statement.bind(file.dev, at: 9)
        try statement.bind(generation, at: 10)
        try statement.bind(trackID, at: 11)
        do {
            _ = try statement.step()
        } catch let error as SQLiteError where error.isConstraintViolation {
            // Belt-and-braces: a racing insert between the pre-flight and the UPDATE would
            // still trip UNIQUE(url); map it to the typed conflict (mirrors moveTrack).
            throw URLConflict(url: key, existingID: nil)
        }
    }
}
