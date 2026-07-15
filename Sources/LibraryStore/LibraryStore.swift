// LibraryStore — the front door to the persistent library database (GRDB-backed).
//
// Rebuilt on GRDB.swift (the GRDB refactor). The former hand-rolled SQLite wrapper
// (SQLiteConnection/SQLiteStatement) + MigrationRunner are gone; this is now a thin
// `Sendable` facade over a GRDB `DatabaseWriter`:
//   • FILE stores use a `DatabasePool` — WAL, a single serialized writer, and REAL
//     concurrent reads (the single-connection actor never had these).
//   • IN-MEMORY stores (":memory:", tests) use a `DatabaseQueue` — a pool can't back
//     an in-memory database (its connections can't share the same memory).
//
// Concurrency (design §4): GRDB's writer serializes writes and multiplexes reads, so
// the store no longer needs an `actor` to serialize access. Every DB touch is a
// self-contained `dbWriter.read { db in … }` / `.write { db in … }` closure — each
// write closure IS one transaction (GRDB opens IMMEDIATE), which makes the old
// "no `await` between two connection calls" invariant structurally impossible: there
// is no long-lived connection handle to interleave, and a closure body is synchronous.
// Only `Sendable` value types cross the boundary; no `Database`/handle ever escapes.
//
// The library store holds TWO kinds of data: a rebuildable CACHE of on-disk files (scan-built
// track/album/artist/genre/FTS rows) AND non-rebuildable USER data (playlists/entries + the track
// user-state columns play_count/loved/rating/last_played/frecency_*). Because of the latter,
// `eraseDatabaseOnSchemaChange` is FALSE (S10.3) — a schema change is an ADDITIVE, frozen-body
// migration that PRESERVES user data; the cache is rebuilt by a re-scan, never by wiping the file.
// Corruption is still quarantined + rebuilt (a genuinely-unreadable file) — the deferred backup/
// export is the durability answer for user data on that last-resort path.

import Foundation
import GRDB
import Synchronization

/// `Sendable` facade over the SQLite-backed library store (GRDB `DatabaseWriter`).
public final class LibraryStore: Sendable {
    /// The GRDB writer. Module-internal so the DAO extensions (same module) can open
    /// `read`/`write` transactions on it; never exposed publicly, no `Database` escapes.
    /// A `DatabasePool` for file stores (concurrent reads), a `DatabaseQueue` in-memory.
    let dbWriter: any DatabaseWriter

    /// The schema version reached after migrate (read back from `schema_info`).
    private let version: Int

    /// A count of FTS `SearchIndex` write operations (sync/delete) performed this
    /// session — a verification hook so the harness can prove a no-op re-scan does
    /// ZERO FTS writes (the idempotency contract, design §4). A `Mutex` because writes
    /// run on GRDB's writer thread while `searchIndexWriteCount()` may read from another.
    let searchIndexWrites = Mutex(0)

    // MARK: - SQL

    /// `PRAGMA integrity_check(1);` — "ok" iff the database file is intact.
    private static let integrityCheckSQL = "PRAGMA integrity_check(1);"
    /// The live `journal_mode` (expected "wal" for a file store).
    private static let journalModePragmaSQL = "PRAGMA journal_mode;"
    /// Whether `foreign_keys` enforcement is ON.
    private static let foreignKeysPragmaSQL = "PRAGMA foreign_keys;"
    /// The live `busy_timeout` in milliseconds.
    private static let busyTimeoutPragmaSQL = "PRAGMA busy_timeout;"
    /// Seed-a-`folders`-row fixture (verification hook, NOT `addRoot`).
    private static let seedFolderRowSQL = "INSERT INTO folders(path, is_root) VALUES (?, ?);"
    /// Set a track's reserved user-state columns (verification hook).
    private static let setUserStateSQL =
        "UPDATE tracks SET play_count = ?, loved = ?, rating = ? WHERE id = ?;"
    /// Read a track's reserved user-state columns (verification hook).
    private static let selectUserStateSQL = "SELECT play_count, loved, rating FROM tracks WHERE id = ?;"
    /// Recently-Played frecency (S10.6): read the prior accumulator + last-play, then write the
    /// updated play_count / last_played / decayed score / projected rank in ONE write transaction
    /// (a read-modify-write — the score/rank are Swift-computed, so this can't be a bare UPDATE;
    /// the single serialized `DatabaseWriter` makes the in-closure read+write atomic, no TOCTOU).
    private static let selectFrecencyStateByIDSQL =
        "SELECT frecency_score, last_played FROM tracks WHERE id = ?;"
    private static let selectFrecencyStateByURLSQL =
        "SELECT frecency_score, last_played FROM tracks WHERE url = ?;"
    private static let recordPlayByIDSQL =
        "UPDATE tracks SET play_count = play_count + 1, last_played = ?, "
            + "frecency_score = ?, frecency_rank = ? WHERE id = ?;"
    private static let recordPlayByURLSQL =
        "UPDATE tracks SET play_count = play_count + 1, last_played = ?, "
            + "frecency_score = ?, frecency_rank = ? WHERE url = ?;"
    /// Read the schema version back from `schema_info` (0 on a fresh, unwritten store).
    private static let selectSchemaVersionSQL = "SELECT version FROM schema_info WHERE id = 1;"

    /// Count rows in `table` (verification hook). `table` is caller-validated against the known
    /// schema table set before interpolation, keeping the identifier injection-safe.
    private static func countRowsSQL(table: String) -> String {
        "SELECT count(*) FROM \(table);"
    }

    /// Open (creating if absent) and migrate the store at `url`. Corruption / a failed
    /// integrity check quarantine the file (+ its `-wal`/`-shm` sidecars) and rebuild
    /// fresh; a schema change is an ADDITIVE migration that PRESERVES data (erase=false,
    /// S10.3). Never crashes, never silently deletes (design §5).
    ///
    /// - Parameters:
    ///   - url: the store file URL (`:memory:` for an in-memory database).
    ///   - appBuild: optional build identifier stored in `schema_info.app_build`.
    public init(url: URL, appBuild: String? = nil) async throws {
        (dbWriter, version) = try LibraryStore.openMigratingAndRepairing(
            url: url, appBuild: appBuild, stamp: StoreQuarantine.defaultStamp()
        )
    }

    /// The default store location: `~/Library/Application Support/AdaptiveSound/
    /// library.sqlite3`. Creates the `AdaptiveSound` directory if needed.
    public static func defaultStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = appSupport.appendingPathComponent("AdaptiveSound", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.sqlite3")
    }

    /// The default artwork cache directory — `~/Library/Application Support/
    /// AdaptiveSound/artwork/`, a sibling of the store (design §4). Created if needed.
    public static func defaultArtworkCacheURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = appSupport
            .appendingPathComponent("AdaptiveSound", isDirectory: true)
            .appendingPathComponent("artwork", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The schema version the store is currently at.
    public func schemaVersion() async -> Int {
        version
    }

    /// Run `PRAGMA integrity_check` on the live store; `true` iff SQLite says "ok".
    public func integrityCheck() async throws -> Bool {
        try await dbWriter.read { db in
            try String.fetchOne(db, sql: Self.integrityCheckSQL) == "ok"
        }
    }

    // MARK: - Pragma inspection (verification hooks)

    /// The live `journal_mode` (expected "wal" for a file store) — asserted by the harness.
    public func journalMode() async throws -> String {
        try await dbWriter.read { db in try String.fetchOne(db, sql: Self.journalModePragmaSQL) ?? "unknown" }
    }

    /// Whether `foreign_keys` enforcement is ON — asserted by the harness.
    public func foreignKeysEnabled() async throws -> Bool {
        try await dbWriter.read { db in try (Int.fetchOne(db, sql: Self.foreignKeysPragmaSQL) ?? 0) == 1 }
    }

    /// The live `busy_timeout` in milliseconds — asserted by the harness.
    public func busyTimeout() async throws -> Int {
        try await dbWriter.read { db in try Int.fetchOne(db, sql: Self.busyTimeoutPragmaSQL) ?? 0 }
    }

    // MARK: - Verification hooks (NOT the DAO)

    /// Count rows in `table`. A minimal read hook so the harness can prove
    /// migration-preserves-data and restart durability. `table` is validated against
    /// the known schema table set to keep the interpolated identifier injection-safe.
    public func countRows(inTable table: String) async throws -> Int {
        guard Schema.expectedTables.contains(table) || table == Schema.ftsTableName else {
            throw SQLiteError.internalError(message: "unknown table for countRows: \(table)")
        }
        return try await dbWriter.read { db in try Int.fetchOne(db, sql: Self.countRowsSQL(table: table)) ?? 0 }
    }

    /// The number of FTS `SearchIndex` write ops (sync/delete) since open — a
    /// verification hook (NOT the DAO) used to prove a no-op re-scan writes nothing.
    public func searchIndexWriteCount() async -> Int {
        searchIndexWrites.withLock { $0 }
    }

    /// Seed a `folders` row (a durable fixture for the migration/restart harness checks).
    /// Returns the new rowid. A verification hook, NOT the `addRoot` DAO op.
    @discardableResult
    public func seedFolderRow(path: String, isRoot: Bool = true) async throws -> Int64 {
        try await dbWriter.write { db in
            try db.execute(
                sql: Self.seedFolderRowSQL,
                arguments: [PathNormalizer.normalizedString(forPath: path), isRoot ? 1 : 0]
            )
            return db.lastInsertedRowID
        }
    }

    /// Set a track's reserved user-state columns (`play_count`/`loved`/`rating`). A
    /// VERIFICATION HOOK, not the DAO. Used to prove these id-keyed values SURVIVE a
    /// move-match (the whole point of preserving `tracks.id` across a move).
    public func setUserState(trackID: Int64, playCount: Int64, loved: Bool, rating: Int64?) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: Self.setUserStateSQL,
                arguments: [playCount, loved ? 1 : 0, rating, trackID]
            )
        }
    }

    /// Read a track's reserved user-state columns — the read side of `setUserState`.
    /// Verification hook, not the DAO. `nil` if no such track.
    public func userState(trackID: Int64) async throws -> TrackUserState? {
        try await dbWriter.read { db in
            guard let row = try Row.fetchOne(
                db, sql: Self.selectUserStateSQL, arguments: [trackID]
            ) else { return nil }
            return TrackUserState(playCount: row[0], loved: (row[1] as Int64) == 1, rating: row[2])
        }
    }

    // MARK: - Play tracking (§12.3, S9.5 — pulled forward from S10)

    /// Count one natural-completion play for the track at `url`: a SINGLE atomic
    /// `UPDATE … SET play_count = play_count + 1, last_played = ?` — no read-modify-write
    /// race, no id round-trip (URL-keyed, normalized via `PathNormalizer`). Increments
    /// commute, so callers may fire this fire-and-forget with no ordering requirement.
    ///
    /// A `url` with no matching row is a SILENT no-op (zero rows affected, NOT an error) —
    /// a play-count write must never throw into the audio path.
    public func incrementPlayCount(url: URL, playedAt: Int64) async throws {
        let key = PathNormalizer.normalizedString(for: url)
        try await dbWriter.write { db in
            guard let row = try Row.fetchOne(db, sql: Self.selectFrecencyStateByURLSQL, arguments: [key]) else {
                return // no matching row — silent no-op (never throw into the audio path)
            }
            let prevScore: Double = row["frecency_score"] ?? 0
            let lastPlayed: Int64? = row["last_played"]
            let updated = Self.frecencyAfterPlay(prevScore: prevScore, lastPlayed: lastPlayed, now: playedAt)
            try db.execute(sql: Self.recordPlayByURLSQL,
                           arguments: [playedAt, updated.score, updated.rank, key])
        }
    }

    /// Count one play by durable `tracks.id` (S10.2 — the queue carries the id, so play-tracking
    /// no longer needs the `url→id` lookup). Silent no-op if the id is absent (never throws into
    /// the audio path).
    public func incrementPlayCount(id trackID: Int64, playedAt: Int64) async throws {
        try await dbWriter.write { db in
            guard let row = try Row.fetchOne(db, sql: Self.selectFrecencyStateByIDSQL, arguments: [trackID]) else {
                return // absent id — silent no-op (never throw into the audio path)
            }
            let prevScore: Double = row["frecency_score"] ?? 0
            let lastPlayed: Int64? = row["last_played"]
            let updated = Self.frecencyAfterPlay(prevScore: prevScore, lastPlayed: lastPlayed, now: playedAt)
            try db.execute(sql: Self.recordPlayByIDSQL,
                           arguments: [playedAt, updated.score, updated.rank, trackID])
        }
    }

    /// The raw frecency state of a track (S10.6 verification hook). A struct (not a tuple) to stay
    /// within the large-tuple lint bound.
    public struct FrecencyState: Sendable {
        public let playCount: Int64
        public let score: Double
        public let rank: Double?
        public let lastPlayed: Int64?
    }

    /// Verification hook (S10.6): the raw frecency state for a track id, for `VerifyLibraryStore`
    /// to assert the accumulator/rank against `frecencyAfterPlay`. `nil` if the id is absent.
    public func frecencyState(id trackID: Int64) async throws -> FrecencyState? {
        try await dbWriter.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT play_count, frecency_score, frecency_rank, last_played FROM tracks WHERE id = ?;",
                arguments: [trackID]
            ) else { return nil }
            return FrecencyState(playCount: row["play_count"], score: row["frecency_score"] ?? 0,
                                 rank: row["frecency_rank"], lastPlayed: row["last_played"])
        }
    }

    // MARK: - Open / repair pipeline

    /// The GRDB `Configuration` shared by every store connection: WAL is implied by
    /// `DatabasePool`; `foreign_keys` ON (design §5); a 5 s busy timeout so a writer
    /// waits under contention rather than failing with `SQLITE_BUSY` immediately.
    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(5)
        return config
    }

    /// Open + migrate the store at `url`. On a rebuild-recoverable failure for a
    /// PRE-EXISTING file — it cannot be opened/queried as a database, or `integrity_check`
    /// fails — the file (+ its `-wal`/`-shm` sidecars) is quarantined and a fresh store is
    /// rebuilt. Never crashes, never silently deletes (design §5). A schema change is an
    /// ADDITIVE, frozen-body migration that PRESERVES user data (erase=false, S10.3).
    private static func openMigratingAndRepairing(
        url: URL, appBuild: String?, stamp: String
    ) throws -> (any DatabaseWriter, Int) {
        let migrator = makeMigrator(appBuild: appBuild)

        // In-memory stores can't be corrupt/quarantined; open + migrate directly.
        if url.path == ":memory:" || url.absoluteString == "file::memory:" {
            let queue = try DatabaseQueue(configuration: makeConfiguration())
            try migrator.migrate(queue)
            return try (queue, readSchemaVersion(queue))
        }

        let fileExisted = FileManager.default.fileExists(atPath: url.path)
        do {
            let pool = try DatabasePool(path: url.path, configuration: makeConfiguration())
            if fileExisted {
                // A pre-existing file must be intact AND not written by a newer app (the
                // downgrade guard — `hasBeenSuperseded` sees a migration id we don't know)
                // before we trust it. GRDB tracks applied migrations in `grdb_migrations`.
                let intact = try pool.read { db in
                    try String.fetchOne(db, sql: Self.integrityCheckSQL) == "ok"
                }
                let superseded = try pool.read { db in try migrator.hasBeenSuperseded(db) }
                if !intact || superseded { throw StoreOpenFailure.rebuildRecoverable }
            }
            do {
                try migrator.migrate(pool)
            } catch {
                // A PRE-EXISTING file whose on-disk schema the current migrator cannot apply —
                // e.g. a store from a prior, non-GRDB migration scheme (app tables present but NOT
                // recorded in `grdb_migrations`, so `migrate` re-runs v1 and collides with the
                // existing tables), or any partially-migrated file. The library is a REBUILDABLE
                // CACHE, so quarantine + rebuild rather than fail to open. A FRESH file that fails
                // to migrate is a genuine bug → propagate.
                guard fileExisted else { throw error }
                throw StoreOpenFailure.rebuildRecoverable
            }
            return try (pool, readSchemaVersion(pool))
        } catch let error where fileExisted && isRebuildRecoverable(error) {
            // A pre-existing file was unusable (corrupt / failed integrity / newer schema / a
            // schema the migrator can't apply). Quarantine it (+ sidecars) and rebuild fresh —
            // the library is a rebuildable cache.
            try StoreQuarantine.quarantine(storeURL: url, stamp: stamp)
            let pool = try DatabasePool(path: url.path, configuration: makeConfiguration())
            try migrator.migrate(pool)
            return try (pool, readSchemaVersion(pool))
        }
    }

    /// A sentinel distinguishing "quarantine + rebuild" from a genuine, propagate error.
    private enum StoreOpenFailure: Error, Equatable {
        case rebuildRecoverable
    }

    /// Whether an open/migrate error means the file is not a usable database (so a
    /// quarantine + rebuild recovers): the explicit sentinel, or a GRDB `DatabaseError`
    /// with a corruption/not-a-db result code.
    private static func isRebuildRecoverable(_ error: Error) -> Bool {
        if error as? StoreOpenFailure == .rebuildRecoverable { return true }
        guard let dbError = error as? DatabaseError else { return false }
        let code = dbError.resultCode.primaryResultCode
        return code == .SQLITE_CORRUPT || code == .SQLITE_NOTADB
    }

    /// Read the schema version back from `schema_info` (0 on a fresh, unwritten store).
    private static func readSchemaVersion(_ writer: any DatabaseWriter) throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: Self.selectSchemaVersionSQL) ?? 0 }
    }

    /// The GRDB `DatabaseMigrator` bringing a fresh/older store to `currentSchemaVersion`.
    ///
    /// `eraseDatabaseOnSchemaChange = FALSE` (S10.3, reversed from the earlier drop-and-recreate
    /// posture): this DB holds NON-rebuildable USER data — playlists/entries, and the track
    /// user-state columns `play_count`/`loved`/`rating`/`last_played`/`frecency_*` — NOT just a
    /// cache of on-disk files. A break-it pass showed the old "wipe on any schema change" rule
    /// silently destroyed that user data (and a separate never-erased store keyed by the reused
    /// `tracks.id` rowid mis-resolved playlists after a rebuild — worse). So migrations are
    /// **additive-only** and every shipped migration body is **frozen** (a schema change is a NEW
    /// appended migration — proven-safe: appending never erases). The DERIVED cache (scan-built
    /// track/album/artist/genre/FTS rows) is still rebuildable — by a RE-SCAN (delete rows +
    /// re-scan), not by wiping the file. Dev reset: add a migration, or delete the DB file by hand.
    static func makeMigrator(appBuild: String?) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration(Schema.MigrationID.v1) { db in
            try Schema.migrateV0toV1(db, appBuild: appBuild, timestamp: nowSeconds())
        }
        migrator.registerMigration(Schema.MigrationID.v2) { db in
            try Schema.migrateV1toV2(db, appBuild: appBuild, timestamp: nowSeconds())
        }
        migrator.registerMigration(Schema.MigrationID.v3) { db in
            try Schema.migrateV2toV3(db, appBuild: appBuild, timestamp: nowSeconds())
        }
        migrator.registerMigration(Schema.MigrationID.v4) { db in
            try Schema.migrateV3toV4(db, appBuild: appBuild, timestamp: nowSeconds())
        }
        return migrator
    }

    /// Current Unix epoch seconds (whole seconds — mtime discipline, design §3).
    /// Module-internal so the DAO extension can stamp `date_added` on insert.
    static func nowSeconds() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    /// Half-life for the Recently-Played frecency decay (design D5): 7 days, in seconds.
    public static let frecencyHalfLifeSeconds: Double = 7 * 24 * 60 * 60

    /// Pure frecency update (S10.6 R2/R7): the new `(score, rank)` after a play at `now`, given the
    /// prior decayed `score` + `lastPlayed`.
    /// - `score = prevScore·2^(−max(0, now−lp)/H) + 1` — first play (`lp == nil`) → `1`; the
    ///   `max(0,…)` clamp blocks a backward clock jump from inflating the decay factor.
    /// - `rank = now + (H/ln2)·ln(score)` — the projected instant at which the score decays to 1;
    ///   `score ≥ 1` always ⇒ `ln ≥ 0` (no domain error), and ordering by `rank` equals ordering by
    ///   current frecency `score·2^(−(t−lp)/H)` at ANY read time `t` (Mozilla-Places projected-rank).
    /// Pure + `internal` so `VerifyLibraryStore` / `swift test` can prove the algorithm directly.
    public static func frecencyAfterPlay(prevScore: Double, lastPlayed: Int64?, now: Int64,
                                         halfLife: Double = frecencyHalfLifeSeconds) -> (score: Double, rank: Double) {
        let score: Double
        if let lastPlayed {
            let age = Double(max(0, now - lastPlayed))
            score = prevScore * pow(2.0, -age / halfLife) + 1.0
        } else {
            score = 1.0
        }
        let rank = Double(now) + (halfLife / log(2.0)) * log(score)
        return (score, rank)
    }
}
