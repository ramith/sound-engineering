// LibraryStore — the actor front door to the persistent library database.
//
// S8.1a FOUNDATION + S8.1b DAO. This file owns: open/create + migrate, the
// App-Support default location, `schemaVersion()`, `integrityCheck()`, and the
// corruption/first-run/downgrade handling (quarantine + rebuild). It also exposes
// a narrow set of verification hooks (`countRows`, `seedFolderRow`) so the
// headless harness can prove migration-preserves-data and restart durability
// without reaching into the connection.
//
// The S8.1b DAO (upsert / moveTrack / facets / loose-file / classify / roots) lives
// in the `LibraryStore+DAO.swift`, `LibraryStore+Reads.swift`, and
// `LibraryStore+Facets.swift` extensions (this file kept small). Those extensions
// use the module-internal `connection` directly — it is never exposed publicly and
// never escapes the actor.
//
// Concurrency contract (design §4): `LibraryStore` is an `actor`. Only `Sendable`
// value types cross its boundary; the `SQLiteConnection` (and its raw `sqlite3*`)
// NEVER escapes. Single writer by construction (actor isolation), WAL-backed
// concurrent reads.

import Foundation

/// Actor-isolated front door to the SQLite-backed library store.
public actor LibraryStore {
    /// The open connection. Module-internal + actor-isolated so the DAO extensions
    /// (same module) can use it; never exposed publicly, never escapes the actor.
    ///
    /// INVARIANT: every method touching this connection must run FULLY synchronously —
    /// no `await` between two connection calls, or the actor's serialization guarantee
    /// breaks under THREADSAFE=2 (a suspended method could interleave a second caller's
    /// statements on the same handle).
    let connection: SQLiteConnection

    /// The on-disk location this store was opened from (nil for `:memory:`).
    public let storeURL: URL?

    /// The schema version the store is at after open/migrate.
    private let version: Int

    /// Open (creating if absent) and migrate the store at `url` to the current
    /// schema. Corruption / `integrity_check` failure / a newer-than-app schema
    /// all trigger quarantine (file + `-wal`/`-shm` sidecars) followed by a fresh
    /// create — never a crash, never a silent delete (design §5).
    ///
    /// - Parameters:
    ///   - url: the store file URL (parent directory must already exist for a
    ///     bespoke URL; `defaultStoreURL()` creates App-Support for you).
    ///   - appBuild: optional build identifier stored in `schema_info.app_build`.
    public init(url: URL, appBuild: String? = nil) async throws {
        storeURL = url
        let opened = try LibraryStore.openMigratingAndRepairing(
            url: url,
            appBuild: appBuild,
            stamp: StoreQuarantine.defaultStamp()
        )
        connection = opened.connection
        version = opened.version
    }

    /// The default store location: `~/Library/Application Support/AdaptiveSound/
    /// library.sqlite3`. Creates the `AdaptiveSound` directory if needed (sandbox
    /// neutral — App Support is inside the container either way, design §7).
    public static func defaultStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("AdaptiveSound", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.sqlite3")
    }

    /// The schema version the store is currently at.
    public func schemaVersion() -> Int {
        version
    }

    /// Run `PRAGMA integrity_check` on the live store; `true` iff SQLite says "ok".
    public func integrityCheck() throws -> Bool {
        try connection.integrityCheck()
    }

    // MARK: - Pragma inspection (verification hooks)

    /// The live `journal_mode` (expected "wal") — asserted by the harness.
    public func journalMode() throws -> String {
        try connection.journalMode()
    }

    /// Whether `foreign_keys` enforcement is ON — asserted by the harness.
    public func foreignKeysEnabled() throws -> Bool {
        try connection.foreignKeysEnabled()
    }

    /// The live `busy_timeout` in milliseconds — asserted by the harness.
    public func busyTimeout() throws -> Int {
        try connection.busyTimeout()
    }

    // MARK: - Verification hooks (NOT the S8.1b DAO)

    /// Count rows in `table`. A minimal read hook so the harness can prove
    /// migration-preserves-data and restart durability without a full DAO.
    /// `table` is validated against the known schema table set to keep the
    /// interpolated identifier injection-safe.
    public func countRows(inTable table: String) throws -> Int {
        guard Schema.expectedTables.contains(table) else {
            throw SQLiteError.internalError(message: "unknown table for countRows: \(table)")
        }
        return try Int(connection.scalarInt("SELECT count(*) FROM \(table);") ?? 0)
    }

    /// Seed a `folders` row (a persistent, FK-free row usable as a durable fixture
    /// for the migration/restart harness checks). Returns the new rowid. This is a
    /// verification hook, NOT the S8.1b `addRoot` DAO op.
    @discardableResult
    public func seedFolderRow(path: String, isRoot: Bool = true) throws -> Int64 {
        let statement = try connection.prepare(
            "INSERT INTO folders(path, is_root) VALUES (?, ?);"
        )
        defer { statement.finalize() }
        try statement.bind(PathNormalizer.normalizedString(forPath: path), at: 1)
        try statement.bind(Int64(isRoot ? 1 : 0), at: 2)
        _ = try statement.step()
        return connection.lastInsertRowID()
    }

    // MARK: - Open / repair pipeline

    /// The result of an open: the live connection plus the schema version reached.
    private struct OpenResult {
        let connection: SQLiteConnection
        let version: Int
    }

    /// Open, integrity-check, and migrate the store at `url`. On ANY
    /// rebuild-recoverable condition — the file cannot be opened as a database
    /// (garbage header / SQLITE_NOTADB / SQLITE_CORRUPT), `integrity_check` fails,
    /// or the schema is newer than this app (downgrade guard) — the file (+ its
    /// `-wal`/`-shm` sidecars) is quarantined and a fresh store is rebuilt. Never
    /// crashes, never silently deletes (design §5). Static so it can run before the
    /// actor's stored properties are initialized.
    private static func openMigratingAndRepairing(
        url: URL,
        appBuild: String?,
        stamp: String
    ) throws -> OpenResult {
        // In-memory stores can't be corrupt/quarantined; open + migrate directly.
        if url.absoluteString == "file::memory:" || url.path == ":memory:" {
            let connection = try SQLiteConnection(path: url.path)
            try MigrationRunner.migrateToCurrent(connection, appBuild: appBuild, timestamp: nowSeconds())
            return try OpenResult(connection: connection, version: connection.userVersion())
        }

        let fileExisted = FileManager.default.fileExists(atPath: url.path)
        do {
            return try openAndMigrate(url: url, appBuild: appBuild, treatFailuresAsCorruption: fileExisted)
        } catch let error as StoreOpenFailure where error == .rebuildRecoverable {
            // A pre-existing file was unusable (corrupt / newer schema). Quarantine
            // it (+ sidecars) and rebuild fresh — the library is a rebuildable cache.
            return try quarantineAndRebuild(url: url, appBuild: appBuild, stamp: stamp)
        }
    }

    /// A sentinel distinguishing "quarantine + rebuild" from a genuine, propagate
    /// error, so `openMigratingAndRepairing` only recovers from the intended cases.
    private enum StoreOpenFailure: Error, Equatable {
        case rebuildRecoverable
    }

    /// Open the connection, integrity-check a pre-existing file, and migrate. When
    /// `treatFailuresAsCorruption` is true (the file already existed), an open-time
    /// corruption code, a failed integrity check, or a too-new schema are all mapped
    /// to `StoreOpenFailure.rebuildRecoverable`; any other error propagates as-is.
    private static func openAndMigrate(
        url: URL,
        appBuild: String?,
        treatFailuresAsCorruption: Bool
    ) throws -> OpenResult {
        let connection: SQLiteConnection
        do {
            connection = try SQLiteConnection(path: url.path)
        } catch let error as SQLiteError where treatFailuresAsCorruption && error.indicatesCorruption {
            // sqlite3_open succeeds lazily, but the opening PRAGMAs hit the garbage
            // header and fail with SQLITE_NOTADB/SQLITE_CORRUPT — treat as corrupt.
            throw StoreOpenFailure.rebuildRecoverable
        }

        // A pre-existing file must pass integrity before we trust it. A freshly
        // created file has no header yet, so skip the check on first run.
        if treatFailuresAsCorruption {
            let intact = (try? connection.integrityCheck()) ?? false
            if !intact {
                connection.close()
                throw StoreOpenFailure.rebuildRecoverable
            }
        }

        do {
            try MigrationRunner.migrateToCurrent(connection, appBuild: appBuild, timestamp: nowSeconds())
        } catch let error as SQLiteError {
            connection.close()
            // Downgrade guard OR mid-migration corruption on an existing file → rebuild.
            if treatFailuresAsCorruption, error.isRebuildRecoverable {
                throw StoreOpenFailure.rebuildRecoverable
            }
            throw error
        }

        return try OpenResult(connection: connection, version: connection.userVersion())
    }

    /// Quarantine the store at `url` (+ sidecars) and create a fresh, migrated one.
    private static func quarantineAndRebuild(
        url: URL,
        appBuild: String?,
        stamp: String
    ) throws -> OpenResult {
        try StoreQuarantine.quarantine(storeURL: url, stamp: stamp)
        let connection = try SQLiteConnection(path: url.path)
        try MigrationRunner.migrateToCurrent(connection, appBuild: appBuild, timestamp: nowSeconds())
        return try OpenResult(connection: connection, version: connection.userVersion())
    }

    /// Current Unix epoch seconds (whole seconds — mtime discipline, design §3).
    /// Module-internal (not private) so the DAO extension can stamp `date_added`
    /// with a real timestamp on insert (SF-1), sharing one definition of "now".
    static func nowSeconds() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
