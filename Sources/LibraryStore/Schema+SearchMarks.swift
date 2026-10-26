// Schema+SearchMarks — the v12 → v13 migration (R1.1-B fix round; break-it BI-P08, review "L2, wider"): the
// search index re-written in form 3 of the one search rule, so a combining mark that follows no word
// character is no word.
//
// Most emoji are followed by a variation selector (U+FE0F, a nonspacing mark); a keycap ends in U+20E3, an
// enclosed character in an enclosing mark. The index's tokenizer keeps every mark in a token
// (`categories 'L* N* Co M*'`, v9), so each emoji left a one-mark "word" behind in the index, and every
// emoji query ("❤️") found every emoji title ("☀️ Summer"). The rule now folds variation selectors and emoji
// skin-tone modifiers away and drops any combining mark that follows no word character, in the index and in
// every query (`SearchRule.normalized`, form 3 — `SearchRule.indexFormVersion`).
//
// ADDITIVE and data-preserving, the v11 pattern: `tracks_fts` is DERIVED from `tracks` (rowid = `tracks.id`)
// and its DDL is unchanged — only what each row holds changes — so the index is emptied and rebuilt from
// `tracks` through the v9 projection (frozen) in the rule's current form (`LibraryStore.rebuildSearchIndex`).
// No user data is named: playlists, entries and the track user-state columns are untouched, and the step
// references nothing a foreign key checks (FTS5 tables have none).

import Foundation
import GRDB

public extension Schema.MigrationID {
    /// v12 → v13: the search index rebuilt in the one search rule's form 3 — stray combining marks dropped,
    /// variation selectors and emoji modifiers folded away (R1.1-B fix round, BI-P08).
    static let v13 = "v13-search-stray-marks"
}

public extension Schema {
    /// Every migration that re-writes the search index, with the form of the one search rule it writes
    /// (`SearchRule.indexFormVersion`), in order. Append one with every new form; VerifyLibraryStore fails
    /// when the rule's form is ahead of the latest one here, or that migration is not registered.
    static let searchIndexForms: [(migration: String, form: Int)] = [
        (MigrationID.v9, 1),
        (MigrationID.v11, 2),
        (MigrationID.v13, 3),
    ]

    /// Migrate v12 → v13: rebuild `tracks_fts` from `tracks`, every row in the search rule's form 3.
    static func migrateV12toV13(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        try LibraryStore.rebuildSearchIndex(db, projection: searchProjectionV9)
        try writeSchemaInfo(db, version: 13, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
