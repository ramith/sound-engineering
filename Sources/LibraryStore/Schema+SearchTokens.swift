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

    /// The searchable-field projection of tracks the v9 re-index introduced — `id, title, artist, album,
    /// genre` — LEFT-JOINed so a track with no artist/genre still resolves; `title` falls back to the filename
    /// `name`, genres are space-joined. The album text is the song's own album title (`tracks.album_title`,
    /// v7): an album row's title IS its songs' album title (S10.8 C2) — and a metadata pass, which leaves
    /// album assignment to its end-of-pass regroup (C2 fix round B2), still indexes the album text at the
    /// song's own write. FROZEN: the re-index migrations v9, v11 and v13 read it, and a track write indexes
    /// through it (`LibraryStore+SearchIndex`); a new projection is a new constant and a new re-index.
    static let searchProjectionV9 = """
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

    /// Drop the v2 index (its tokenizer can't be altered in place).
    private static let dropFtsStatement = "DROP TABLE tracks_fts;"

    /// Migrate v8 → v9: recreate `tracks_fts` with the v9 tokenizer and rebuild it from `tracks`, every
    /// row normalised as a track write normalises it.
    static func migrateV8toV9(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        try db.execute(sql: dropFtsStatement)
        try db.execute(sql: createV9FtsStatement)
        try LibraryStore.rebuildSearchIndex(db, projection: searchProjectionV9)
        try writeSchemaInfo(db, version: 9, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
