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
// What the index holds is each field in the search rule's form (`SearchRule.normalized` — form
// `SearchRule.indexFormVersion`: NFKC, R1.1-A / council C-61; the zero-width joiners, variation selectors and
// emoji modifiers folded away and stray combining marks dropped, R1.1-B): the tokenizer compares code points
// and does not normalise, so a title stored decomposed (an NFD filename from an older Mac drive or a zip)
// would never meet what the user types, and a Sinhala conjunct written with its joiner would split in two.
// The re-index migrations (v9, v11, v13) write every row through the projection frozen in the migration that
// introduced it (`Schema.searchProjectionV9`) and the rule's current form — the index is derived data, and
// the last re-index must leave it in the form the queries use — so an upgraded index and a fresh one can't
// disagree.
//
// HIDDEN PREMISE (guard at S10+): the `artist`/`album`/`genre` FTS columns are
// DENORMALIZED copies of the facet names, correct today only because those names are
// immutable natural keys (resolve-by-name → new row; never renamed in place). Any future
// in-place facet editing MUST re-sync every affected track's FTS row — this per-track
// seam will NOT catch a facet-table UPDATE.

import Foundation
import GRDB

extension LibraryStore {
    /// The searchable-field projection a track write indexes: the latest re-index migration's frozen one
    /// (`Schema.searchProjectionV9`). A new projection is a new frozen constant AND a re-index migration
    /// that writes it — never an edit of the one in use.
    private static let searchRowsSelect = Schema.searchProjectionV9

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

    /// Rebuild the whole index from `tracks` through `projection` (a re-index migration's frozen one), every
    /// row in the search rule's current form — the re-index migrations' backfill (`Schema.migrateV8toV9`,
    /// `migrateV10toV11`, `migrateV12toV13`), inside their transaction.
    static func rebuildSearchIndex(_ db: Database, projection: String) throws {
        try db.execute(sql: deleteAllSearchRowsSQL)
        let rows = try Row.fetchCursor(db, sql: projection + ";")
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
