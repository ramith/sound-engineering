// Schema — the v1 library-store DDL (design §3) and the v0→v1 migration step.
//
// S8.1a. This is the FIRST production schema, so v1 = create-all + seed the
// "unknown artist" sentinel `artists(id=0)` that backs the M1 total album key
// (untagged albums collapse to one row on `(title, album_artist_id=0, year=0)`).
//
// Locked founder defaults baked into `tracks`:
//   • reserved user-track-state columns: play_count / rating / loved / last_played
//   • url stored NFC-precomposed, standardized absolute path (see PathNormalizer);
//     symlinks NOT resolved
//   • folder_id … ON DELETE SET NULL (removing a folder keeps its tracks loose)
//   • album natural key is TOTAL: album_artist_id DEFAULT 0, year DEFAULT 0
//
// Metadata columns exist now but are populated later (S8.3), so there is no
// S8.1→S8.3 migration. Playlist tables are deferred (M7); they will be the first
// real V1→V2 migration.

import Foundation

/// The schema version this build of `LibraryStore` targets. The migration runner
/// brings any older store up to this; a store newer than this triggers the
/// downgrade guard (quarantine + rebuild).
///
/// v2 (S9.2) adds the `tracks_fts` FTS5 full-text search table + its v1→v2
/// backfill — the first real V1→V2 migration. Bumping this constant and adding the
/// `toVersion: 2` step to `MigrationRunner.productionMigrations` MUST happen in one
/// change: bump-without-step → `.migrationMissing` (store fails to open, not
/// quarantined); step-without-bump → `tracks_fts` is silently never created.
public let currentSchemaVersion = 2

/// The reserved "unknown artist" sentinel rowid seeded at v1 for the M1 album key.
public let unknownArtistID: Int64 = 0

/// Static schema DDL + the v0→v1 migration.
public enum Schema {
    /// The complete set of `CREATE` statements for schema v1, ordered so a
    /// referenced table is created before its referrers (SQLite tolerates forward
    /// FK references, but explicit ordering keeps intent clear and pragma-safe).
    public static let createV1Statements: [String] = [
        """
        CREATE TABLE schema_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            version INTEGER NOT NULL,
            app_build TEXT,
            created_at INTEGER NOT NULL,
            migrated_at INTEGER NOT NULL);
        """,
        // folders: dev/inode capture each ROOT's on-disk identity (lstat), so a
        // case-variant or differently-spelled path for the SAME directory on a
        // case-insensitive volume is caught as a duplicate at `addRoot` — not
        // registered as a second root (QS3). v1-direct (no populated store; mirrors
        // tracks.dev). Populated for roots only; NULL otherwise (never matches).
        """
        CREATE TABLE folders (
            id INTEGER PRIMARY KEY,
            parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            is_root INTEGER NOT NULL DEFAULT 0,
            bookmark BLOB,
            last_scanned INTEGER,
            dev INTEGER,
            inode INTEGER,
            UNIQUE(path));
        """,
        "CREATE INDEX idx_folders_parent ON folders(parent_id);",
        """
        CREATE TABLE artists (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            sort_name TEXT,
            UNIQUE(name));
        """,
        """
        CREATE TABLE genres (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            UNIQUE(name));
        """,
        // artwork before albums/tracks: both reference artwork(content_hash).
        """
        CREATE TABLE artwork (
            content_hash TEXT PRIMARY KEY,
            cache_path TEXT NOT NULL,
            width INTEGER,
            height INTEGER,
            byte_size INTEGER,
            ref_count INTEGER NOT NULL DEFAULT 0);
        """,
        // M1: album natural key is TOTAL. album_artist_id DEFAULT 0 references the
        // seeded sentinel; year DEFAULT 0 = "unknown". UNIQUE(title, album_artist_id,
        // year) with non-NULL defaults collapses untagged albums to ONE row.
        """
        CREATE TABLE albums (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            album_artist_id INTEGER NOT NULL DEFAULT 0 REFERENCES artists(id) ON DELETE SET DEFAULT,
            year INTEGER NOT NULL DEFAULT 0,
            artwork_key TEXT REFERENCES artwork(content_hash) ON DELETE SET NULL,
            UNIQUE(title, album_artist_id, year));
        """,
        "CREATE INDEX idx_albums_artist ON albums(album_artist_id);",
        "CREATE INDEX idx_albums_year ON albums(year);",
        // tracks: stable id identity + nullable folder (loose files) + the delta/move
        // signature (file_size, mtime, inode, dev — dev added to v1 DIRECTLY in S8.2a,
        // M-B: no populated production store exists, so no migration) + metadata columns
        // (NULL until S8.3) + reserved user-track-state columns.
        """
        CREATE TABLE tracks (
            id INTEGER PRIMARY KEY,
            url TEXT NOT NULL,
            folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
            relative_path TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL,
            format TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            mtime INTEGER NOT NULL,
            inode INTEGER,
            dev INTEGER,
            content_hash TEXT,
            album_id INTEGER REFERENCES albums(id) ON DELETE SET NULL,
            artist_id INTEGER REFERENCES artists(id) ON DELETE SET NULL,
            title TEXT,
            track_no INTEGER,
            disc_no INTEGER,
            year INTEGER,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            sample_rate INTEGER,
            bit_depth INTEGER,
            channels INTEGER,
            artwork_key TEXT REFERENCES artwork(content_hash) ON DELETE SET NULL,
            date_added INTEGER NOT NULL,
            last_seen_scan INTEGER NOT NULL DEFAULT 0,
            metadata_scanned INTEGER NOT NULL DEFAULT 0,
            play_count INTEGER NOT NULL DEFAULT 0,
            rating INTEGER,
            loved INTEGER NOT NULL DEFAULT 0,
            last_played INTEGER,
            UNIQUE(url));
        """,
        "CREATE INDEX idx_tracks_folder ON tracks(folder_id);",
        "CREATE INDEX idx_tracks_album ON tracks(album_id);",
        "CREATE INDEX idx_tracks_artist ON tracks(artist_id);",
        "CREATE INDEX idx_tracks_year ON tracks(year);",
        "CREATE INDEX idx_tracks_added ON tracks(date_added);",
        "CREATE INDEX idx_tracks_lastseen ON tracks(last_seen_scan);",
        "CREATE INDEX idx_tracks_album_order ON tracks(album_id, disc_no, track_no);",
        // The move-signature columns S8.4 matches an orphan-plus-new-path on — indexed
        // now, with the columns that exist to serve it, so S8.4's matcher is an index
        // seek, not a table scan per candidate move (A1).
        "CREATE INDEX idx_tracks_dev_inode ON tracks(dev, inode);",
        // The S8.3 metadata-pass driving query: rows with metadata_scanned == 0 (never
        // attempted). Records the *attempt* (the scan generation), decoupled from
        // outcome — a genuinely tagless file is marked and never re-extracted (the
        // anti-loop guarantee); a retagged file is reset to 0 by the upsert (below).
        "CREATE INDEX idx_tracks_meta_scanned ON tracks(metadata_scanned);",
        """
        CREATE TABLE track_genres (
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            genre_id INTEGER NOT NULL REFERENCES genres(id) ON DELETE CASCADE,
            PRIMARY KEY (track_id, genre_id));
        """,
        "CREATE INDEX idx_trackgenres_genre ON track_genres(genre_id);",
    ]

    /// The table names schema v1 must contain — asserted by the harness (SCHEMA-1).
    public static let expectedTables: [String] = [
        "schema_info", "folders", "artists", "genres", "artwork", "albums",
        "tracks", "track_genres",
    ]

    /// Migrate an empty (v0) database to v1: create every table + index, then seed
    /// the sentinel artist row and the `schema_info` provenance row. Runs inside the
    /// caller's transaction (the migration runner opens `BEGIN IMMEDIATE`).
    ///
    /// - Parameters:
    ///   - connection: the open connection (already inside a transaction).
    ///   - appBuild: an optional build identifier stored in `schema_info.app_build`.
    ///   - timestamp: creation/migration Unix epoch seconds (injected for testability).
    public static func migrateV0toV1(_ connection: SQLiteConnection, appBuild: String?, timestamp: Int64) throws {
        for statement in createV1Statements {
            try connection.exec(statement)
        }
        try seedSentinelArtist(connection)
        try writeSchemaInfo(connection, version: 1, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }

    // MARK: - v2: FTS5 full-text search (S9.2, design §4)

    /// The FTS5 virtual table (schema v2). Its rowid IS `tracks.id`, so the
    /// `SearchIndex` seam maintains one row per track by rowid (delete-then-insert) —
    /// no separate id column. `unicode61 remove_diacritics 2` folds case + accents
    /// (so "bjork" matches "Björk").
    /// The FTS5 search table name (v2). Kept as a constant so read hooks can
    /// validate it as an injection-safe identifier alongside `expectedTables`.
    public static let ftsTableName = "tracks_fts"

    public static let createV2FtsStatement = """
    CREATE VIRTUAL TABLE tracks_fts USING fts5(
        title, artist, album, genre,
        tokenize = 'unicode61 remove_diacritics 2');
    """

    /// Backfill `tracks_fts` from every existing track. **All LEFT JOINs + COALESCE**
    /// so a track with no artist/album/genre still yields exactly one FTS row (an INNER
    /// JOIN would silently drop it from the index). `title` falls back to the filename
    /// `name` (matching `LibraryTrackDisplay`); genres are space-joined via a correlated
    /// `group_concat`. rowid = `t.id` so the row is addressable by the seam.
    public static let backfillV2FtsStatement = """
    INSERT INTO tracks_fts(rowid, title, artist, album, genre)
    SELECT t.id,
           COALESCE(NULLIF(t.title, ''), t.name),
           COALESCE(ar.name, ''),
           COALESCE(al.title, ''),
           COALESCE((SELECT group_concat(g.name, ' ')
                     FROM track_genres tg JOIN genres g ON g.id = tg.genre_id
                     WHERE tg.track_id = t.id), '')
    FROM tracks t
    LEFT JOIN artists ar ON ar.id = t.artist_id
    LEFT JOIN albums  al ON al.id = t.album_id;
    """

    /// Probe whether this SQLite build has the FTS5 extension, by creating and
    /// dropping a throwaway temp virtual table. FTS5 is REQUIRED for v2, so the
    /// migration calls this first and throws a clear error rather than failing
    /// cryptically at `CREATE VIRTUAL TABLE`. (System libsqlite3 on macOS ships FTS5;
    /// this is cheap insurance against a future toolchain regression.)
    public static func fts5IsAvailable(_ connection: SQLiteConnection) -> Bool {
        do {
            try connection.exec("CREATE VIRTUAL TABLE temp.__as_fts5_probe USING fts5(x);")
            try connection.exec("DROP TABLE temp.__as_fts5_probe;")
            return true
        } catch {
            return false
        }
    }

    /// Migrate v1 → v2: create `tracks_fts` and backfill it. Runs inside the migration
    /// runner's single `BEGIN IMMEDIATE` — so it uses `connection.exec` DIRECTLY and
    /// must NOT open its own transaction. `fts5Available` is injectable so the harness
    /// can force the unavailable path (CAP); production passes the real probe.
    public static func migrateV1toV2(
        _ connection: SQLiteConnection,
        appBuild: String?,
        timestamp: Int64,
        fts5Available: (SQLiteConnection) -> Bool = fts5IsAvailable
    ) throws {
        guard fts5Available(connection) else {
            throw SQLiteError.fts5Unavailable
        }
        try connection.exec(createV2FtsStatement)
        try connection.exec(backfillV2FtsStatement)
        // Refresh provenance to v2; `created_at` is preserved by the ON CONFLICT SET.
        try writeSchemaInfo(connection, version: 2, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }

    /// Seed the reserved `artists(id=0)` "unknown artist" sentinel backing the M1
    /// total album key. `INSERT OR IGNORE` keeps it idempotent.
    public static func seedSentinelArtist(_ connection: SQLiteConnection) throws {
        let statement = try connection.prepare(
            "INSERT OR IGNORE INTO artists(id, name, sort_name) VALUES (?, ?, ?);"
        )
        defer { statement.finalize() }
        try statement.bind(unknownArtistID, at: 1)
        try statement.bind("Unknown Artist", at: 2)
        try statement.bind("Unknown Artist", at: 3)
        _ = try statement.step()
    }

    /// Upsert the single `schema_info` row (id = 1). `created_at` is preserved on
    /// re-migration; `version`/`migrated_at`/`app_build` are refreshed.
    public static func writeSchemaInfo(
        _ connection: SQLiteConnection,
        version: Int,
        appBuild: String?,
        createdAt: Int64,
        migratedAt: Int64
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO schema_info(id, version, app_build, created_at, migrated_at)
            VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                version = excluded.version,
                app_build = excluded.app_build,
                migrated_at = excluded.migrated_at;
            """
        )
        defer { statement.finalize() }
        try statement.bind(Int64(version), at: 1)
        try statement.bind(appBuild, at: 2)
        try statement.bind(createdAt, at: 3)
        try statement.bind(migratedAt, at: 4)
        _ = try statement.step()
    }
}
