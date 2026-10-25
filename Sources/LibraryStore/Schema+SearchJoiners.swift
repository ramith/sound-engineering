// Schema+SearchJoiners — the v10 → v11 migration (R1.1-B, US-R1F-14): the search index re-written in the
// one search rule's form, so a Sinhala conjunct is one word whether or not it was written with its joiner.
//
// The index's tokenizer reads the zero-width joiner (U+200D) and non-joiner (U+200C) — format characters —
// as word breaks: "ශ්‍රී" (Sri, written with its joiner) indexed as two words, "ශ්" and "රී", and a query typed
// without the joiner, "ශ්රී", found nothing. The one search rule folds both away in the index and in every
// query (`SearchRule.normalized`; founder, 2026-10-25 — decided as recommended at R1.1-B's plan check).
//
// ADDITIVE and data-preserving, the v9 pattern: `tracks_fts` is DERIVED from `tracks` (rowid = `tracks.id`),
// and its DDL is unchanged — only what each row holds changes — so the index is emptied and rebuilt from
// `tracks` through the write path's own projection and normalisation (`LibraryStore.rebuildSearchIndex`).
// No user data is named: playlists, entries and the track user-state columns are untouched, and the step
// references nothing a foreign key checks (FTS5 tables have none).

import Foundation
import GRDB

public extension Schema.MigrationID {
    /// v10 → v11: the search index rebuilt in the one search rule's form — the zero-width joiner and
    /// non-joiner folded away (R1.1-B, US-R1F-14).
    static let v11 = "v11-search-joiners"
}

public extension Schema {
    /// Migrate v10 → v11: rebuild `tracks_fts` from `tracks`, every row in the search rule's form.
    static func migrateV10toV11(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        try LibraryStore.rebuildSearchIndex(db)
        try writeSchemaInfo(db, version: 11, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
