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
//
// GRDB refactor: the migration bodies run inside a GRDB `DatabaseMigrator` step (one
// registered migration per version), so they take a `Database` and use `db.execute`.
// `DatabaseMigrator` owns the applied-migration bookkeeping (its `grdb_migrations`
// table) — `schema_info` is kept purely as app-facing provenance (version/build/dates).

import Foundation
import GRDB

/// The schema version this build of `LibraryStore` targets — recorded in `schema_info`
/// by the migrations and asserted by the verify harness. GRDB's `DatabaseMigrator` brings any
/// older store up to the latest registered migration; a store carrying a migration id this
/// build does not know trips the downgrade guard (`hasBeenSuperseded` → quarantine + rebuild).
///
/// v2 (S9.2) adds the `tracks_fts` FTS5 table + its v1→v2 backfill. Adding a future version
/// means: register a new migration in `LibraryStore.makeMigrator` (with a new `Schema.MigrationID`)
/// whose body writes `schema_info` at the new version, AND bump this constant — the migration
/// creates/backfills the schema; this constant is the value the harness expects to read back.
public let currentSchemaVersion = 4

/// The reserved "unknown artist" sentinel rowid seeded at v1 for the M1 album key.
public let unknownArtistID: Int64 = 0

/// Static schema DDL + the v0→v1 migration.
public enum Schema {
    /// The GRDB `DatabaseMigrator` step identifiers, shared between the production migrator
    /// (`LibraryStore.makeMigrator`) and the verification harness. They MUST match: GRDB's
    /// downgrade guard (`hasBeenSuperseded`) treats a file carrying an applied identifier the
    /// current migrator does not know as "written by a newer app" → quarantine + rebuild. A
    /// harness that seeds a v1 store and then hands it to `LibraryStore` must therefore use the
    /// SAME identifier for v1, or the store would wrongly quarantine the seeded fixture.
    public enum MigrationID {
        /// v0 → v1: create every table + index and seed the unknown-artist sentinel.
        public static let v1 = "v1-create-all"
        /// v1 → v2: the `tracks_fts` FTS5 table + backfill (S9.2).
        public static let v2 = "v2-fts5"
        /// v2 → v3: the `playlists` + `playlist_entries` tables + the seeded built-in
        /// "current" queue playlist (S10.1). Durability across schema change is DEFERRED
        /// (design §0.1): `eraseDatabaseOnSchemaChange` stays true pre-R1.
        public static let v3 = "v3-playlists"
        /// v3 → v4: `tracks.frecency_score` + `tracks.frecency_rank` (+ index) for the
        /// Recently-Played frecency ordering (S10.6). ADDITIVE (ALTER ADD COLUMN); play counts
        /// reset in practice via the delete-rebuild posture (founder D9). `frecency_rank` is
        /// nullable so a legacy/never-scored played row sorts last (NULLs last in DESC) rather
        /// than corrupting the order.
        public static let v4 = "v4-frecency"
    }

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
        // v3 (S10.1): playlists + ordered entries.
        "playlists", "playlist_entries",
    ]

    /// Migrate an empty (v0) database to v1: create every table + index, then seed
    /// the sentinel artist row and the `schema_info` provenance row. Runs inside the
    /// caller's transaction (the migration runner opens `BEGIN IMMEDIATE`).
    ///
    /// - Parameters:
    ///   - connection: the open connection (already inside a transaction).
    ///   - appBuild: an optional build identifier stored in `schema_info.app_build`.
    ///   - timestamp: creation/migration Unix epoch seconds (injected for testability).
    public static func migrateV0toV1(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV1Statements {
            try db.execute(sql: statement)
        }
        try seedSentinelArtist(db)
        try writeSchemaInfo(db, version: 1, appBuild: appBuild,
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
    /// Create the throwaway temp virtual table used to probe for the FTS5 extension.
    private static let fts5ProbeCreateSQL = "CREATE VIRTUAL TABLE temp.__as_fts5_probe USING fts5(x);"
    /// Drop the FTS5 probe temp table.
    private static let fts5ProbeDropSQL = "DROP TABLE temp.__as_fts5_probe;"

    public static func fts5IsAvailable(_ db: Database) -> Bool {
        do {
            try db.execute(sql: fts5ProbeCreateSQL)
            try db.execute(sql: fts5ProbeDropSQL)
            return true
        } catch {
            return false
        }
    }

    /// Migrate v1 → v2: create `tracks_fts` and backfill it. Runs inside the migrator's
    /// single migration transaction — so it uses `db.execute` DIRECTLY and must NOT open
    /// its own transaction. `fts5Available` is injectable so the harness can force the
    /// unavailable path (CAP); production passes the real probe. (GRDB on Apple platforms
    /// links SQLite with FTS5, so the probe effectively always passes — kept as cheap
    /// insurance + the harness's injection seam.)
    public static func migrateV1toV2(
        _ db: Database,
        appBuild: String?,
        timestamp: Int64,
        fts5Available: (Database) -> Bool = fts5IsAvailable
    ) throws {
        guard fts5Available(db) else {
            throw SQLiteError.fts5Unavailable
        }
        try db.execute(sql: createV2FtsStatement)
        try db.execute(sql: backfillV2FtsStatement)
        // Refresh provenance to v2; `created_at` is preserved by the ON CONFLICT SET.
        try writeSchemaInfo(db, version: 2, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }

    // MARK: - v3: playlists + ordered entries (S10.1, design §3)

    /// The reserved name of the built-in, non-deletable "current" playlist — the play queue
    /// (design §0.3). `is_builtin = 1`; exempt from the user-name UNIQUE index.
    public static let builtinCurrentPlaylistName = "current"

    /// The `CREATE` statements for schema v3 (design §3). `playlists` first (referenced by
    /// `playlist_entries`). `playlist_entries` carries its OWN id + `position`, so the same
    /// `track_id` may appear multiple times in one playlist (US-PLIST-01). Name uniqueness is
    /// scoped to user playlists (`WHERE is_builtin = 0`) so the reserved "current" can't collide
    /// (design §0.4). `track_id → tracks.id ON DELETE CASCADE`: a genuinely-deleted track (file
    /// gone / explicit delete) drops out of its playlists (design §0.2).
    public static let createV3Statements: [String] = [
        """
        CREATE TABLE playlists (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            is_builtin INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL);
        """,
        // At most ONE built-in playlist, enforced as a DB invariant (idempotent bootstrap).
        "CREATE UNIQUE INDEX idx_playlists_one_builtin ON playlists(is_builtin) WHERE is_builtin = 1;",
        // Duplicate USER playlist names prevented (design §0.4); the built-in is exempt.
        "CREATE UNIQUE INDEX idx_playlists_name_user ON playlists(name) WHERE is_builtin = 0;",
        """
        CREATE TABLE playlist_entries (
            id INTEGER PRIMARY KEY,
            playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            added_at INTEGER NOT NULL);
        """,
        "CREATE INDEX idx_playlist_entries_playlist ON playlist_entries(playlist_id, position);",
        "CREATE INDEX idx_playlist_entries_track ON playlist_entries(track_id);",
    ]

    /// Seed the built-in "current" queue playlist. `INSERT OR IGNORE` on the single-builtin
    /// invariant (`idx_playlists_one_builtin`) keeps it idempotent, like `seedSentinelArtist`.
    private static let seedBuiltinCurrentPlaylistSQL =
        "INSERT OR IGNORE INTO playlists(name, is_builtin, created_at) VALUES (?, 1, ?);"

    public static func seedBuiltinCurrentPlaylist(_ db: Database, timestamp: Int64) throws {
        try db.execute(sql: seedBuiltinCurrentPlaylistSQL,
                       arguments: [builtinCurrentPlaylistName, timestamp])
    }

    /// Migrate v2 → v3: create the playlist tables + indexes, then seed the built-in "current"
    /// queue playlist. Runs inside the migrator's single migration transaction (uses `db.execute`
    /// directly; opens no transaction of its own). Additive — no `tracks` backfill.
    public static func migrateV2toV3(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV3Statements {
            try db.execute(sql: statement)
        }
        try seedBuiltinCurrentPlaylist(db, timestamp: timestamp)
        try writeSchemaInfo(db, version: 3, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }

    /// The `ALTER`/`CREATE` statements for schema v4 (S10.6): the frecency ordering columns on
    /// `tracks`. `frecency_score` is the decayed-play accumulator; `frecency_rank` is the derived,
    /// INDEXED read key (`last_played + (H/ln2)·ln(score)` — the Mozilla-Places projected-rank
    /// trick: current frecency is monotonic in it, so `ORDER BY frecency_rank DESC` is the exact
    /// order with no read-time decay math + no `now`). `frecency_rank` is nullable → a never-played
    /// / legacy-unscored row sorts LAST (NULLs last in DESC), never mis-ordering real rows. The
    /// plain index carries the rowid as its trailing key, so `ORDER BY frecency_rank DESC, id DESC`
    /// is index-driven (no temp b-tree).
    public static let createV4Statements: [String] = [
        "ALTER TABLE tracks ADD COLUMN frecency_score REAL NOT NULL DEFAULT 0;",
        "ALTER TABLE tracks ADD COLUMN frecency_rank REAL;",
        "CREATE INDEX idx_tracks_frecency_rank ON tracks(frecency_rank);",
    ]

    /// Migrate v3 → v4: add the frecency columns + index. Additive — no `tracks` backfill (counts
    /// reset via the delete-rebuild posture; the nullable rank keeps the read correct either way).
    public static func migrateV3toV4(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV4Statements {
            try db.execute(sql: statement)
        }
        try writeSchemaInfo(db, version: 4, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }

    /// Seed the reserved `artists(id=0)` sentinel (`INSERT OR IGNORE` keeps it idempotent).
    private static let seedSentinelArtistSQL =
        "INSERT OR IGNORE INTO artists(id, name, sort_name) VALUES (?, ?, ?);"

    /// Seed the reserved `artists(id=0)` "unknown artist" sentinel backing the M1
    /// total album key. `INSERT OR IGNORE` keeps it idempotent.
    public static func seedSentinelArtist(_ db: Database) throws {
        try db.execute(
            sql: seedSentinelArtistSQL,
            arguments: [unknownArtistID, "Unknown Artist", "Unknown Artist"]
        )
    }

    /// Upsert the single `schema_info` row (id = 1). `created_at` is preserved on re-migration
    /// (out of the ON CONFLICT SET); `version`/`migrated_at`/`app_build` are refreshed.
    private static let writeSchemaInfoSQL = """
    INSERT INTO schema_info(id, version, app_build, created_at, migrated_at)
    VALUES (1, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        version = excluded.version,
        app_build = excluded.app_build,
        migrated_at = excluded.migrated_at;
    """

    /// Upsert the single `schema_info` row (id = 1). `created_at` is preserved on
    /// re-migration; `version`/`migrated_at`/`app_build` are refreshed.
    public static func writeSchemaInfo(
        _ db: Database,
        version: Int,
        appBuild: String?,
        createdAt: Int64,
        migratedAt: Int64
    ) throws {
        try db.execute(
            sql: writeSchemaInfoSQL,
            arguments: [Int64(version), appBuild, createdAt, migratedAt]
        )
    }
}
