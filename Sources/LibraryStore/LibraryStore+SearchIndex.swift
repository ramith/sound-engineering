// LibraryStore+SearchIndex — the S9.2 FTS write-path seam (design §4).
//
// ONE internal seam maintains `tracks_fts` (schema v2). Every track mutation that
// changes a searchable field, or removes a row, calls exactly one of these — so
// completeness is a single provable invariant ("every write/delete site calls
// syncSearchRow or deleteSearchRows") instead of scattered inline FTS SQL, and no
// SQL trigger has to reach across the artist/album/genre joins.
//
// The FTS row's rowid IS `tracks.id`, so a track is addressed directly by rowid;
// an update is delete-then-insert. Callers run these INSIDE their own transaction
// (the per-track metadata txn, the scan batch, the sweep txn), so these methods
// never open one — they are synchronous actor-isolated helpers per the store
// invariant.
//
// Wired sites (design §4): upsertOne (genuine .new insert only — a no-op re-scan
// does ZERO FTS writes), applyMetadataLocked (after replaceGenres), moveMatchedLocked
// (it rewrites `name`, the pre-metadata FTS title), delete / deleteTrackRows (covers
// removeRoot), and sweepOrphans (BEFORE its tracks DELETE). `moveTrack` (url only)
// and the facet sweep are deliberately NOT wired (no searchable field changes).
//
// HIDDEN PREMISE (guard at S10+): the `artist`/`album`/`genre` FTS columns are
// DENORMALIZED copies of the facet names, correct today only because those names are
// immutable natural keys (resolve-by-name → new row; never renamed in place). If a
// future feature adds in-place facet editing (rename an artist, fix an album title,
// merge duplicates), that path MUST re-sync every affected track's FTS row — the
// per-track seam here will NOT catch a facet-table UPDATE.

import Foundation

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

    /// (Re)index track `trackID` in `tracks_fts`: read its searchable fields and
    /// delete-then-insert its FTS row (rowid = id). A no-op if the track vanished.
    func syncSearchRow(trackID: Int64) throws {
        let select = try connection.prepare(LibraryStore.searchRowSelect)
        defer { select.finalize() }
        try select.bind(trackID, at: 1)
        guard try select.step() else { return } // track gone; nothing to index

        let title = select.columnText(0) ?? ""
        let artist = select.columnText(1) ?? ""
        let album = select.columnText(2) ?? ""
        let genre = select.columnText(3) ?? ""

        try deleteSearchRows(ids: [trackID])
        let insert = try connection.prepare(
            "INSERT INTO tracks_fts(rowid, title, artist, album, genre) VALUES (?, ?, ?, ?, ?);"
        )
        defer { insert.finalize() }
        try insert.bind(trackID, at: 1)
        try insert.bind(title, at: 2)
        try insert.bind(artist, at: 3)
        try insert.bind(album, at: 4)
        try insert.bind(genre, at: 5)
        _ = try insert.step()
        searchIndexWrites += 1 // verification hook: proves a no-op re-scan writes nothing
    }

    /// Remove the FTS rows for `ids` (a per-id prepared reset-loop, mirroring
    /// `deleteTrackRows` — the id set is caller-supplied and potentially large, so it
    /// is never spliced into SQL). A no-op for an empty set.
    func deleteSearchRows(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        searchIndexWrites += 1
        let statement = try connection.prepare("DELETE FROM tracks_fts WHERE rowid = ?;")
        defer { statement.finalize() }
        for id in ids {
            statement.reset()
            statement.clearBindings()
            try statement.bind(id, at: 1)
            _ = try statement.step()
        }
    }

    /// Delete the FTS rows for the tracks a folder-scoped orphan sweep is about to
    /// remove — a single set-membership DELETE mirroring `sweepOrphans`'s own predicate
    /// (`folder_id IN (…) AND last_seen_scan < ?`). MUST run BEFORE the `tracks` DELETE:
    /// once the rows are gone the sub-select finds nothing and the FTS rows would leak.
    func deleteSearchRowsForSweep(inFolders folderIDs: [Int64], olderThan generation: Int64) throws {
        guard !folderIDs.isEmpty else { return }
        searchIndexWrites += 1
        let placeholders = folderIDs.map { _ in "?" }.joined(separator: ", ")
        let statement = try connection.prepare(
            """
            DELETE FROM tracks_fts WHERE rowid IN (
                SELECT id FROM tracks WHERE folder_id IN (\(placeholders)) AND last_seen_scan < ?);
            """
        )
        defer { statement.finalize() }
        var index: Int32 = 1
        for folderID in folderIDs {
            try statement.bind(folderID, at: index)
            index += 1
        }
        try statement.bind(generation, at: index)
        _ = try statement.step()
    }
}
