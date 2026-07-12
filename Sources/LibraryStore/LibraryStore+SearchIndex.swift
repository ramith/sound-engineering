// LibraryStore+SearchIndex — the FTS write-path seam (design §4), GRDB-backed.
//
// ONE internal seam maintains `tracks_fts` (schema v2). Every track mutation that
// changes a searchable field, or removes a row, calls exactly one of these — so
// completeness is a single provable invariant ("every write/delete site calls
// syncSearchRow or deleteSearchRows") instead of scattered inline FTS SQL.
//
// The FTS row's rowid IS `tracks.id`; an update is delete-then-insert. Each method takes
// the caller's `Database` and runs INSIDE the caller's write transaction (per-track
// metadata txn, scan batch, sweep txn) — none opens its own.
//
// HIDDEN PREMISE (guard at S10+): the `artist`/`album`/`genre` FTS columns are
// DENORMALIZED copies of the facet names, correct today only because those names are
// immutable natural keys (resolve-by-name → new row; never renamed in place). Any future
// in-place facet editing MUST re-sync every affected track's FTS row — this per-track
// seam will NOT catch a facet-table UPDATE.

import Foundation
import GRDB

extension LibraryStore {
    /// The searchable-field projection for one track, LEFT-JOINed so a track with no
    /// artist/album/genre still resolves; `title` falls back to the filename `name`,
    /// genres are space-joined. Identical column semantics to the v2 backfill, so a
    /// re-synced row matches what the migration would have produced.
    private static let searchRowSelect = """
    SELECT COALESCE(NULLIF(t.title, ''), t.name),
           COALESCE(ar.name, ''),
           COALESCE(al.title, ''),
           COALESCE((SELECT group_concat(g.name, ' ')
                     FROM track_genres tg JOIN genres g ON g.id = tg.genre_id
                     WHERE tg.track_id = t.id), '')
    FROM tracks t
    LEFT JOIN artists ar ON ar.id = t.artist_id
    LEFT JOIN albums  al ON al.id = t.album_id
    WHERE t.id = ?;
    """

    /// Insert one FTS row (rowid = `tracks.id`) with its denormalized searchable columns.
    private static let insertSearchRowSQL =
        "INSERT INTO tracks_fts(rowid, title, artist, album, genre) VALUES (?, ?, ?, ?, ?);"
    /// Delete a single FTS row by rowid (== `tracks.id`).
    private static let deleteSearchRowSQL = "DELETE FROM tracks_fts WHERE rowid = ?;"

    /// The set-membership FTS delete mirroring `sweepOrphans`'s predicate. `placeholders` is the
    /// `?,?,…` list for the folder ids (the id set is bound, never spliced into SQL).
    private static func deleteSearchRowsForSweepSQL(placeholders: String) -> String {
        """
        DELETE FROM tracks_fts WHERE rowid IN (
            SELECT id FROM tracks WHERE folder_id IN (\(placeholders)) AND last_seen_scan < ?);
        """
    }

    /// (Re)index track `trackID` in `tracks_fts`: read its searchable fields and
    /// delete-then-insert its FTS row (rowid = id). A no-op if the track vanished.
    func syncSearchRow(_ db: Database, trackID: Int64) throws {
        guard let row = try Row.fetchOne(db, sql: LibraryStore.searchRowSelect, arguments: [trackID]) else {
            return // track gone; nothing to index
        }
        let title: String = row[0] ?? ""
        let artist: String = row[1] ?? ""
        let album: String = row[2] ?? ""
        let genre: String = row[3] ?? ""

        try deleteSearchRows(db, ids: [trackID])
        try db.execute(
            sql: Self.insertSearchRowSQL,
            arguments: [trackID, title, artist, album, genre]
        )
        searchIndexWrites.withLock { $0 += 1 } // verification hook: proves a no-op re-scan writes nothing
    }

    /// Remove the FTS rows for `ids` (one DELETE per id — GRDB caches the prepared statement;
    /// the id set is caller-supplied and potentially large, so it is never spliced into SQL).
    /// A no-op for an empty set.
    func deleteSearchRows(_ db: Database, ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        searchIndexWrites.withLock { $0 += 1 }
        for id in ids {
            try db.execute(sql: Self.deleteSearchRowSQL, arguments: [id])
        }
    }

    /// Delete the FTS rows for the tracks a folder-scoped orphan sweep is about to remove — a
    /// single set-membership DELETE mirroring `sweepOrphans`'s predicate. MUST run BEFORE the
    /// `tracks` DELETE: once the rows are gone the sub-select finds nothing and FTS rows leak.
    func deleteSearchRowsForSweep(_ db: Database, inFolders folderIDs: [Int64], olderThan generation: Int64) throws {
        guard !folderIDs.isEmpty else { return }
        searchIndexWrites.withLock { $0 += 1 }
        let placeholders = databaseQuestionMarks(count: folderIDs.count)
        try db.execute(
            sql: Self.deleteSearchRowsForSweepSQL(placeholders: placeholders),
            arguments: StatementArguments(folderIDs + [generation])
        )
    }
}
