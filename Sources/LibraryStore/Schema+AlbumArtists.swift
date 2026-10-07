// Schema+AlbumArtists — the v6 → v7 migration (S10.8 C2, album artists; amended by the C2 fix
// round before any real library ran it — only test stores have v7, and `make reset-test-library`
// resets those).
//
// Four changes, all data-preserving and appended (never an edit of a SHIPPED body):
//   1. `tracks` gains the RAW album inputs `AlbumGrouping` reads — `album_title`,
//      `album_artist_tag`, `compilation` — so a regroup never has to re-read a file. They are
//      backfilled (trimmed) from today's album rows: under the M1 key an album row held EXACTLY the
//      song's album title + album-artist tag (the id-0 sentinel meant "no tag"). The compilation
//      flag was never read, so it starts at 0 until the one-time re-read (`derivedDataVersion`).
//   2. `albums` gains `folder_key` ("" = a tagged album) and its unique key becomes
//      (title, album_artist_id, folder_key): two untagged same-title albums in different folders
//      can coexist (ALB-05), and the YEAR leaves the key (fix round C1 — the album shows its songs'
//      most common year instead). v6 rows that differed ONLY by year are merged first: their
//      songs move to the lowest id of the set (albums are DERIVED data; the re-read regroups them
//      anyway). A song pointing at an album row that no longer exists is unlinked (also derived).
//      SQLite cannot alter a table-level UNIQUE, so this is its documented table rebuild (new →
//      copy → drop → rename), the form `LibraryStore.makeMigrator` sanctions: every kept row is
//      copied with its id, so `tracks.album_id` stays valid. The key is now a UNIQUE INDEX, so a
//      future change to it is an index drop/recreate (like v6), not another rebuild.
//   3. `schema_info` gains `derived_version` — the derived-data version stamp the store compares
//      with `LibraryStore.derivedDataVersion` at open to trigger a one-time full tag re-read — and
//      `regroup_owed`, the durable "a pass wrote tags, the end-of-pass album regroup has not run
//      yet" flag (fix round B2: a pass no longer regroups per write, so a pass cut off at quit
//      must still get its regroup at the next launch).
//   4. FOREIGN KEYS (fix round A3): the step runs with foreign keys OFF (so `DROP TABLE albums`
//      never cascades `SET NULL` into `tracks.album_id`) and WITHOUT GRDB's whole-database check —
//      one unrelated stale reference anywhere (a `tracks.artwork_key` …) must not fail the upgrade.
//      Instead it checks, before commit, the references it can break: every row pointing INTO
//      `albums`. (The rebuilt rows' own references are copied byte-for-byte.)
// No user data is touched: playlists, entries and the track user-state columns are not named.

import Foundation
import GRDB

public extension Schema {
    /// The v7 statements, in order (see the file header for each step's why).
    static let createV7Statements: [String] = [
        // 1. The raw album inputs on tracks (+ the single-write regroup's title lookup index).
        "ALTER TABLE tracks ADD COLUMN album_title TEXT;",
        "ALTER TABLE tracks ADD COLUMN album_artist_tag TEXT;",
        "ALTER TABLE tracks ADD COLUMN compilation INTEGER NOT NULL DEFAULT 0;",
        "CREATE INDEX idx_tracks_album_title ON tracks(album_title);",
        """
        UPDATE tracks SET
            album_title = (SELECT NULLIF(trim(al.title), '') FROM albums al WHERE al.id = tracks.album_id),
            album_artist_tag = (SELECT NULLIF(trim(ar.name), '') FROM albums al
                                JOIN artists ar ON ar.id = al.album_artist_id
                                WHERE al.id = tracks.album_id AND al.album_artist_id <> 0)
        WHERE album_id IS NOT NULL;
        """,
        // 2. Move every song onto the lowest album id of its (title, album artist) — merging the rows
        //    that differed only by year. A song whose album row is gone finds no row: min() of
        //    nothing is NULL, so it is unlinked (derived data — the re-read regroups it).
        """
        UPDATE tracks SET album_id = (
            SELECT min(kept.id) FROM albums al
            JOIN albums kept ON kept.title = al.title AND kept.album_artist_id = al.album_artist_id
            WHERE al.id = tracks.album_id)
        WHERE album_id IS NOT NULL;
        """,
        // 2b. The albums rebuild: the new key, ids of the kept rows copied verbatim.
        """
        CREATE TABLE albums_v7 (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            album_artist_id INTEGER NOT NULL DEFAULT 0 REFERENCES artists(id) ON DELETE SET DEFAULT,
            year INTEGER NOT NULL DEFAULT 0,
            artwork_key TEXT REFERENCES artwork(content_hash) ON DELETE SET NULL,
            folder_key TEXT NOT NULL DEFAULT '');
        """,
        """
        INSERT INTO albums_v7(id, title, album_artist_id, year, artwork_key)
        SELECT id, title, album_artist_id, year, artwork_key FROM albums
        WHERE id IN (SELECT min(id) FROM albums GROUP BY title, album_artist_id);
        """,
        "DROP TABLE albums;",
        "ALTER TABLE albums_v7 RENAME TO albums;",
        "CREATE UNIQUE INDEX idx_albums_key ON albums(title, album_artist_id, folder_key);",
        "CREATE INDEX idx_albums_artist ON albums(album_artist_id);",
        "CREATE INDEX idx_albums_year ON albums(year);",
        // 3. The derived-data version stamp (0 → the store's first open bumps it) and the
        //    end-of-pass regroup debt.
        "ALTER TABLE schema_info ADD COLUMN derived_version INTEGER NOT NULL DEFAULT 0;",
        "ALTER TABLE schema_info ADD COLUMN regroup_owed INTEGER NOT NULL DEFAULT 0;",
    ]

    /// Migrate v6 → v7: album artists (S10.8 C2). Registered with GRDB's deferred foreign-key
    /// check DISABLED (`LibraryStore.makeMigrator`), so it runs with foreign keys off and checks
    /// its own references before the migrator commits (file header, step 4).
    static func migrateV6toV7(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV7Statements {
            try db.execute(sql: statement)
        }
        try checkReferences(db, into: "albums")
        try writeSchemaInfo(db, version: 7, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }

    /// Throw on the first row (in any table) whose foreign key points into `table` at a row that
    /// is not there — a migration's scoped stand-in for GRDB's whole-database check: it verifies
    /// what the step itself could break and ignores unrelated references elsewhere.
    static func checkReferences(_ db: Database, into table: String) throws {
        let violations = try db.foreignKeyViolations()
        while let violation = try violations.next() {
            if violation.destinationTable == table {
                throw violation.databaseError(db)
            }
        }
    }
}
