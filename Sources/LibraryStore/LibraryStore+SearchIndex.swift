// LibraryStore+SearchIndex — the FTS write-path seam (design §4), GRDB-backed.
//
// ONE internal seam maintains `tracks_fts` (schema v2; its tokenizer since v9). Every track
// mutation that changes a searchable field, or removes a row, calls exactly one of these — so
// completeness is a single provable invariant ("every write/delete site calls
// syncSearchRow or deleteSearchRows") instead of scattered inline FTS SQL.
//
// The FTS row's rowid IS `tracks.id`; an update is delete-then-insert. Each method takes
// the caller's `Database` and runs INSIDE the caller's write transaction (per-track
// metadata txn, scan batch, sweep txn) — none opens its own.
//
// What the index holds is each field in the search rule's form (`SearchRule.normalized`: NFKC, R1.1-A /
// council C-61, and the zero-width joiner and non-joiner folded away, R1.1-B): the tokenizer compares
// code points and does not normalise, so a title stored decomposed (an NFD filename from an older Mac
// drive or a zip) would never meet what the user types, and a Sinhala conjunct written with its joiner
// would split in two. The v9 and v11 rebuilds write every row through the same projection and
// normalisation as a track write, so an upgraded index and a fresh one can't disagree.
//
// HIDDEN PREMISE (guard at S10+): the `artist`/`album`/`genre` FTS columns are
// DENORMALIZED copies of the facet names, correct today only because those names are
// immutable natural keys (resolve-by-name → new row; never renamed in place). Any future
// in-place facet editing MUST re-sync every affected track's FTS row — this per-track
// seam will NOT catch a facet-table UPDATE.

import Foundation
import GRDB

extension LibraryStore {
    /// The searchable-field projection of tracks — `id, title, artist, album, genre` — LEFT-JOINed so a
    /// track with no artist/genre still resolves; `title` falls back to the filename `name`, genres
    /// are space-joined. The album text is the song's own album title (`tracks.album_title`, v7): an
    /// album row's title IS its songs' album title (S10.8 C2) — and a metadata pass, which leaves album
    /// assignment to its end-of-pass regroup (C2 fix round B2), still indexes the album text at the
    /// song's own write.
    private static let searchRowsSelect = """
    SELECT t.id,
           COALESCE(NULLIF(t.title, ''), t.name),
           COALESCE(ar.name, ''),
           COALESCE(t.album_title, ''),
           COALESCE((SELECT group_concat(g.name, ' ')
                     FROM track_genres tg JOIN genres g ON g.id = tg.genre_id
                     WHERE tg.track_id = t.id), '')
    FROM tracks t
    LEFT JOIN artists ar ON ar.id = t.artist_id
    """

    /// One track's searchable fields (`searchRowsSelect`, by id).
    private static let searchRowSelect = searchRowsSelect + "\nWHERE t.id = ?;"

    /// Insert one FTS row (rowid = `tracks.id`) with its denormalized searchable columns.
    private static let insertSearchRowSQL =
        "INSERT INTO tracks_fts(rowid, title, artist, album, genre) VALUES (?, ?, ?, ?, ?);"
    /// Delete a single FTS row by rowid (== `tracks.id`).
    private static let deleteSearchRowSQL = "DELETE FROM tracks_fts WHERE rowid = ?;"
    /// Empty the FTS index (the v9 rebuild's first step).
    private static let deleteAllSearchRowsSQL = "DELETE FROM tracks_fts;"

    /// (Re)index track `trackID` in `tracks_fts`: read its searchable fields and
    /// delete-then-insert its FTS row (rowid = id). A no-op if the track vanished.
    func syncSearchRow(_ db: Database, trackID: Int64) throws {
        guard let row = try Row.fetchOne(db, sql: LibraryStore.searchRowSelect, arguments: [trackID]) else {
            return // track gone; nothing to index
        }
        try deleteSearchRows(db, ids: [trackID])
        try Self.insertSearchRow(db, row)
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

    /// Rebuild the whole index from `tracks`, every row as `syncSearchRow` writes it — the v9 and v11
    /// migrations' backfill (`Schema.migrateV8toV9`, `Schema.migrateV10toV11`), inside their transaction.
    static func rebuildSearchIndex(_ db: Database) throws {
        try db.execute(sql: deleteAllSearchRowsSQL)
        let rows = try Row.fetchCursor(db, sql: searchRowsSelect + ";")
        while let row = try rows.next() {
            try insertSearchRow(db, row)
        }
    }

    /// Insert one projection row (`searchRowsSelect`) as its FTS row, every field in the search rule's
    /// form (`SearchRule.normalized`).
    private static func insertSearchRow(_ db: Database, _ row: Row) throws {
        let id: Int64 = row[0]
        let fields: [String] = (1 ... 4).map { index in
            let field: String? = row[index]
            return SearchRule.normalized(field ?? "")
        }
        try db.execute(sql: insertSearchRowSQL, arguments: [id, fields[0], fields[1], fields[2], fields[3]])
    }
}
