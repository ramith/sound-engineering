// Schema+AlbumArtists — the v6 → v7 migration (S10.8 C2, album artists; amended by the C2 fix
// rounds before any real library ran it — only test stores have v7, and `make reset-test-library`
// resets those). A store an earlier amendment left at v7 is REFUSED at open (`v7ShapeProblem`).
//
// Four changes, all data-preserving and appended (never an edit of a SHIPPED body):
//   1. `tracks` gains the RAW album inputs `AlbumGrouping` reads — `album_title`,
//      `album_artist_tag`, `compilation` — so a regroup never has to re-read a file. They are
//      backfilled (trimmed) from today's album rows: under the M1 key an album row held EXACTLY the
//      song's album title + album-artist tag (the id-0 sentinel meant "no tag"). The compilation
//      flag was never read, so it starts at 0 until the one-time re-read (`derivedDataVersion`).
//   2. `albums` gains `folder_key` ("" = a tagged album) and `edition_year` (0 = not split by
//      year), and its unique key becomes (title, album_artist_id, folder_key, edition_year): two
//      untagged same-title albums in different folders can coexist (ALB-05), and the YEAR is no
//      longer identity — it only splits a group that holds two albums (`AlbumGrouping+Years`); the
//      plain `year` column is what the album SHOWS. Every v6 row is copied with its id and its year
//      as `edition_year`, so the v6 key still fits and `tracks.album_id` stays valid (albums are
//      DERIVED data — the re-read regroups them). A song pointing at an album row that no longer
//      exists is unlinked (also derived). SQLite cannot alter a table-level UNIQUE, so this is its
//      documented table rebuild (new → copy → drop → rename), the form `LibraryStore.makeMigrator`
//      sanctions. The key is now a UNIQUE INDEX, so a future change to it is an index
//      drop/recreate (like v6), not another rebuild.
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
        // 2. Unlink songs from album rows that are gone (derived — the re-read regroups them), then
        //    rebuild `albums` with the new key, every row copied with its id and its year.
        "UPDATE tracks SET album_id = NULL WHERE album_id IS NOT NULL AND album_id NOT IN (SELECT id FROM albums);",
        """
        CREATE TABLE albums_v7 (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            album_artist_id INTEGER NOT NULL DEFAULT 0 REFERENCES artists(id) ON DELETE SET DEFAULT,
            year INTEGER NOT NULL DEFAULT 0,
            artwork_key TEXT REFERENCES artwork(content_hash) ON DELETE SET NULL,
            folder_key TEXT NOT NULL DEFAULT '',
            edition_year INTEGER NOT NULL DEFAULT 0);
        """,
        """
        INSERT INTO albums_v7(id, title, album_artist_id, year, artwork_key, edition_year)
        SELECT id, title, album_artist_id, year, artwork_key, year FROM albums;
        """,
        "DROP TABLE albums;",
        "ALTER TABLE albums_v7 RENAME TO albums;",
        "CREATE UNIQUE INDEX idx_albums_key ON albums(title, album_artist_id, folder_key, edition_year);",
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

    /// The columns the amended v7 adds, by table — an earlier amendment's v7 lacks some.
    private static let v7Columns: [(table: String, columns: [String])] = [
        ("tracks", ["album_title", "album_artist_tag", "compilation"]),
        ("albums", ["folder_key", "edition_year"]),
        ("schema_info", ["derived_version", "regroup_owed"]),
    ]

    /// The amended v7's album key (`idx_albums_key`, unique), in column order.
    private static let v7AlbumKeyColumns = ["title", "album_artist_id", "folder_key", "edition_year"]

    /// nil when `db` has the shape the CURRENT v7 creates, else what differs. v7 was amended in place
    /// twice before any real library ran it (S10.8 C2), so a dev/test store an earlier amendment
    /// migrated records v7 as applied — GRDB never re-runs it — yet lacks columns or has the old
    /// album key, and every metadata pass would fail on it (`no such column: regroup_owed`, an
    /// `ON CONFLICT` matching no key). The open path refuses such a store, untouched.
    static func v7ShapeProblem(_ db: Database) throws -> String? {
        for (table, columns) in v7Columns {
            let present = try Set(db.columns(in: table).map(\.name))
            if let missing = columns.first(where: { !present.contains($0) }) {
                return "\(table).\(missing) is missing"
            }
        }
        let key = try db.indexes(on: "albums").first { $0.name == "idx_albums_key" }
        guard let key, key.isUnique, key.columns == v7AlbumKeyColumns else {
            return "the album key is \(key.map(\.columns) ?? []), not \(v7AlbumKeyColumns)"
        }
        return nil
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
