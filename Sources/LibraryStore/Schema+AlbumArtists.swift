// Schema+AlbumArtists — the v6 → v7 migration (S10.8 C2, album artists).
//
// Three changes, all data-preserving and appended (never an edit of a shipped body):
//   1. `tracks` gains the RAW album inputs `AlbumGrouping` reads — `album_title`,
//      `album_artist_tag`, `compilation` — so a regroup never has to re-read a file. They are
//      backfilled from today's album rows: under the M1 key an album row held EXACTLY the song's
//      album title + album-artist tag (the id-0 sentinel meant "no tag"). The compilation flag
//      was never read, so it starts at 0 until the one-time re-read (`derivedDataVersion`).
//   2. `albums` gains `folder_key` ("" = a tagged album) and its unique key widens from
//      (title, album_artist_id, year) to (title, album_artist_id, year, folder_key), so two
//      untagged same-title albums in different folders can coexist (ALB-05). SQLite cannot alter
//      a table-level UNIQUE, so this is its documented table rebuild (new → copy → drop →
//      rename), the form `LibraryStore.makeMigrator` sanctions: `albums` is DERIVED data, every
//      row is copied with its id (so `tracks.album_id` stays valid), the wider key cannot reject
//      an existing row, and GRDB runs the migration with foreign keys OFF (no cascade on the
//      drop) then checks them before commit. The key is now a UNIQUE INDEX, so a future change
//      to it is an index drop/recreate (like v6), not another rebuild.
//   3. `schema_info` gains `derived_version` — the derived-data version stamp the store compares
//      with `LibraryStore.derivedDataVersion` at open to trigger a one-time full tag re-read.
// No user data is touched: playlists, entries and the track user-state columns are not named.

import Foundation
import GRDB

public extension Schema {
    /// The v7 statements, in order (see the file header for each step's why).
    static let createV7Statements: [String] = [
        // 1. The raw album inputs on tracks (+ the regroup's title-scoped lookup index).
        "ALTER TABLE tracks ADD COLUMN album_title TEXT;",
        "ALTER TABLE tracks ADD COLUMN album_artist_tag TEXT;",
        "ALTER TABLE tracks ADD COLUMN compilation INTEGER NOT NULL DEFAULT 0;",
        "CREATE INDEX idx_tracks_album_title ON tracks(album_title);",
        """
        UPDATE tracks SET
            album_title = (SELECT al.title FROM albums al WHERE al.id = tracks.album_id),
            album_artist_tag = (SELECT ar.name FROM albums al JOIN artists ar ON ar.id = al.album_artist_id
                                WHERE al.id = tracks.album_id AND al.album_artist_id <> 0)
        WHERE album_id IS NOT NULL;
        """,
        // 2. The albums rebuild: widen the unique key with folder_key; ids copied verbatim.
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
        SELECT id, title, album_artist_id, year, artwork_key FROM albums;
        """,
        "DROP TABLE albums;",
        "ALTER TABLE albums_v7 RENAME TO albums;",
        "CREATE UNIQUE INDEX idx_albums_key ON albums(title, album_artist_id, year, folder_key);",
        "CREATE INDEX idx_albums_artist ON albums(album_artist_id);",
        "CREATE INDEX idx_albums_year ON albums(year);",
        // 3. The derived-data version stamp (0 → the store's first open bumps it).
        "ALTER TABLE schema_info ADD COLUMN derived_version INTEGER NOT NULL DEFAULT 0;",
    ]

    /// Migrate v6 → v7: album artists (S10.8 C2). Runs inside the migrator's single transaction
    /// with foreign keys deferred (GRDB's default), which the albums rebuild relies on.
    static func migrateV6toV7(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV7Statements {
            try db.execute(sql: statement)
        }
        try writeSchemaInfo(db, version: 7, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
