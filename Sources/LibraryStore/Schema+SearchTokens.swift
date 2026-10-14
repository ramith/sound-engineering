// Schema+SearchTokens — the v8 → v9 migration (R1.1-A, council C-61 / KI-LIB-11): search reads a word
// in any script, however its text is stored.
//
// Two faults of the v2 search index:
//   • its tokenizer took FTS5 unicode61's default token characters, "L* N* Co": every combining mark
//     (Unicode category M) was a SEPARATOR. A Sinhala vowel sign is one, so "මාල" (necklace), "මිල"
//     (price) and "මුල" (root) all indexed as the same two letters and each query found all three; the
//     same held for every Indic script, Thai and more. FTS5's own remedy (§4.3.1): add the marks to
//     the token categories — "L* N* Co M*". `remove_diacritics 2` still folds a Latin letter's
//     accents (Björk = Bjork), and only those: the fold table is Latin, so й stays й and a Sinhala
//     vowel sign stays part of its word.
//   • the tokenizer compares code points and normalises nothing, so a title stored decomposed (an NFD
//     filename) never met what the user types. Every index row is now written in one normal form
//     (`LibraryStore.searchText`), as is every query.
//
// ADDITIVE and data-preserving: `tracks_fts` is DERIVED from `tracks` (rowid = `tracks.id`), and a
// virtual table's tokenizer can't be altered, so the index is dropped, recreated and rebuilt from
// `tracks` through the write path's own projection (`LibraryStore.rebuildSearchIndex`). No user data is
// named: playlists, entries and the track user-state columns are untouched, and the step references
// nothing a foreign key checks (FTS5 tables have none).

import Foundation
import GRDB

public extension Schema {
    /// The v9 search index: the v2 columns, every mark a token character (FTS5 §4.3.1).
    static let createV9FtsStatement = """
    CREATE VIRTUAL TABLE tracks_fts USING fts5(
        title, artist, album, genre,
        tokenize = "unicode61 remove_diacritics 2 categories 'L* N* Co M*'");
    """

    /// Drop the v2 index (its tokenizer can't be altered in place).
    private static let dropFtsStatement = "DROP TABLE tracks_fts;"

    /// Migrate v8 → v9: recreate `tracks_fts` with the v9 tokenizer and rebuild it from `tracks`, every
    /// row normalised as a track write normalises it.
    static func migrateV8toV9(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        try db.execute(sql: dropFtsStatement)
        try db.execute(sql: createV9FtsStatement)
        try LibraryStore.rebuildSearchIndex(db)
        try writeSchemaInfo(db, version: 9, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
