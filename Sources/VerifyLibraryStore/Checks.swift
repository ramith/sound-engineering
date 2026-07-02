// Checks — the S8.1a schema/migration/corruption/durability verification cases.
//
// Companion to main.swift (which owns the top-level driver + `fail`). Each check
// returns a `Bool` (true = PASS) and prints a numbered PASS/FAIL line in the
// VerifyAUGraph idiom. All temp databases live under `test-data/` (never /tmp),
// are UUID-unique, and are cleaned up by the driver on overall success (kept on
// failure for post-mortem).
//
// The harness drives the store's PUBLIC foundation directly (SQLiteConnection,
// MigrationRunner, Schema, StoreQuarantine) to prove the runner mechanically —
// exactly the "let the harness use SQLiteConnection directly" path the design
// permits. The `LibraryStore` actor is exercised for the end-to-end open/repair
// and durability paths.

import Foundation
import LibraryStore

// MARK: - Shared fixture helpers

/// A fixed, deterministic quarantine stamp so SCHEMA-5 can assert the resulting
/// filenames exactly (the design requires the stamp be injectable/testable).
let testQuarantineStamp = "TESTSTAMP-00000000"

/// A fixed timestamp for migrations so provenance rows are deterministic.
let testTimestamp: Int64 = 1_700_000_000

/// Seed `count` `folders` rows on an open connection (a persistent, FK-free
/// fixture usable to prove migration/restart preserves data). Returns the paths.
@discardableResult
func seedFolders(_ connection: SQLiteConnection, count: Int, prefix: String) throws -> [String] {
    var paths: [String] = []
    let statement = try connection.prepare("INSERT INTO folders(path, is_root) VALUES (?, 1);")
    defer { statement.finalize() }
    for index in 0 ..< count {
        let path = "/Music/\(prefix)-\(index)"
        statement.reset()
        statement.clearBindings()
        try statement.bind(path, at: 1)
        _ = try statement.step()
        paths.append(path)
    }
    return paths
}

/// A test-only v1→v2 migration that adds a NULLABLE column to `folders` and bumps
/// the provenance row — proves the runner mechanically (SCHEMA-3).
func testMigrationV1toV2(addingColumn column: String) -> Migration {
    Migration(toVersion: 2) { connection in
        try connection.exec("ALTER TABLE folders ADD COLUMN \(column) TEXT;")
        try Schema.writeSchemaInfo(connection, version: 2, appBuild: "test-v2",
                                   createdAt: testTimestamp, migratedAt: testTimestamp)
    }
}

// MARK: - SCHEMA-1 — fresh create

/// SCHEMA-1: a fresh store opens at v1 with integrity ok, WAL + foreign_keys +
/// busy_timeout set, and every expected table present.
func checkFreshCreate(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let version = await store.schemaVersion()
        guard version == currentSchemaVersion else {
            printFail(number, "fresh create: schema version \(version) != \(currentSchemaVersion)")
            return false
        }
        guard try await store.integrityCheck() else {
            printFail(number, "fresh create: integrity_check not ok")
            return false
        }
        let journal = try await store.journalMode()
        guard journal.lowercased() == "wal" else {
            printFail(number, "fresh create: journal_mode is '\(journal)', expected wal")
            return false
        }
        guard try await store.foreignKeysEnabled() else {
            printFail(number, "fresh create: foreign_keys not ON")
            return false
        }
        let timeout = try await store.busyTimeout()
        guard timeout > 0 else {
            printFail(number, "fresh create: busy_timeout is \(timeout), expected > 0")
            return false
        }
        // Every expected table must exist + the sentinel artist row must be seeded.
        if let missing = await firstMissingTable(store: store) {
            printFail(number, "fresh create: expected table '\(missing)' missing")
            return false
        }
        let artistCount = try await store.countRows(inTable: "artists")
        guard artistCount == 1 else {
            printFail(number, "fresh create: expected 1 seeded artist (sentinel), found \(artistCount)")
            return false
        }
        printPass(number, "fresh create: v\(version), integrity ok, WAL + foreign_keys + "
            + "busy_timeout(\(timeout)ms) set, all \(Schema.expectedTables.count) tables present, "
            + "unknown-artist sentinel seeded")
        return true
    } catch {
        printFail(number, "fresh create threw: \(error)")
        return false
    }
}

/// Returns the first expected table absent from the store, or nil if all present.
/// Uses `countRows` (which validates the table name against the schema set and
/// runs a `SELECT count(*)`, throwing if the table does not exist).
func firstMissingTable(store: LibraryStore) async -> String? {
    for table in Schema.expectedTables {
        do {
            _ = try await store.countRows(inTable: table)
        } catch {
            return table
        }
    }
    return nil
}

// MARK: - SCHEMA-2 — first-run idempotency

/// SCHEMA-2: opening the SAME fresh DB twice is idempotent — still v1, integrity
/// ok, still exactly one (sentinel) artist, no duplicate schema_info rows.
func checkIdempotentReopen(number: Int, url: URL) async -> Bool {
    do {
        _ = try await LibraryStore(url: url, appBuild: "verify") // first open
        let store = try await LibraryStore(url: url, appBuild: "verify") // second open
        let version = await store.schemaVersion()
        guard version == currentSchemaVersion else {
            printFail(number, "idempotent reopen: version \(version) != \(currentSchemaVersion)")
            return false
        }
        guard try await store.integrityCheck() else {
            printFail(number, "idempotent reopen: integrity_check not ok")
            return false
        }
        let artistCount = try await store.countRows(inTable: "artists")
        guard artistCount == 1 else {
            printFail(number, "idempotent reopen: artist count \(artistCount) != 1 (sentinel duplicated?)")
            return false
        }
        let schemaInfoCount = try await store.countRows(inTable: "schema_info")
        guard schemaInfoCount == 1 else {
            printFail(number, "idempotent reopen: schema_info has \(schemaInfoCount) rows, expected 1")
            return false
        }
        printPass(number, "first-run idempotency: reopening a fresh DB leaves v\(version), "
            + "integrity ok, 1 sentinel artist, 1 schema_info row")
        return true
    } catch {
        printFail(number, "idempotent reopen threw: \(error)")
        return false
    }
}

// MARK: - SCHEMA-3 — migration preserves data across a version bump

/// SCHEMA-3: with a TEST-ONLY v1→v2 (adds a nullable column), seed rows at v1,
/// run the runner to v2, and assert EVERY row survived + the new column defaults
/// to NULL. Proves the runner mechanically (v1 is the first production schema).
func checkMigrationPreservesData(number: Int, url: URL) -> Bool {
    do {
        // Bring an empty DB to v1 and seed rows.
        let seededPaths: [String]
        do {
            let connection = try SQLiteConnection(path: url.path)
            defer { connection.close() }
            try MigrationRunner.migrateToCurrent(connection, appBuild: "verify", timestamp: testTimestamp)
            seededPaths = try seedFolders(connection, count: 5, prefix: "v1seed")
            guard try connection.userVersion() == 1 else {
                printFail(number, "migration preserves data: pre-migration version != 1")
                return false
            }
        }

        // Reopen and migrate v1 -> v2 via the runner with the test-only step.
        let connection = try SQLiteConnection(path: url.path)
        defer { connection.close() }
        let migrations = MigrationRunner.productionMigrations(appBuild: "verify", timestamp: testTimestamp)
            + [testMigrationV1toV2(addingColumn: "test_note")]
        try MigrationRunner.migrate(connection, migrations: migrations, targetVersion: 2)

        guard try connection.userVersion() == 2 else {
            printFail(number, "migration preserves data: post-migration version != 2")
            return false
        }
        let folderCount = try Int(connection.scalarInt("SELECT count(*) FROM folders;") ?? -1)
        guard folderCount == seededPaths.count else {
            printFail(number, "migration preserves data: \(folderCount) folders survived, "
                + "expected \(seededPaths.count)")
            return false
        }
        // The new column must exist AND default to NULL for every pre-existing row.
        let nonNull = try Int(connection.scalarInt(
            "SELECT count(*) FROM folders WHERE test_note IS NOT NULL;"
        ) ?? -1)
        guard nonNull == 0 else {
            printFail(number, "migration preserves data: new column non-NULL for \(nonNull) rows, expected 0")
            return false
        }
        printPass(number, "migration-runner preserves data: v1->v2 (test-only ADD COLUMN) kept all "
            + "\(folderCount) seeded rows; new nullable column defaults NULL")
        return true
    } catch {
        printFail(number, "migration preserves data threw: \(error)")
        return false
    }
}

// MARK: - SCHEMA-4 — migration is transactional

/// A test-only step that seeds a row THEN throws — the runner must roll the whole
/// transaction back, leaving user_version + data at the pre-migration state.
struct MigrationTestError: Error {}

/// SCHEMA-4: a throwing v1->v2 migration leaves the store at v1 with its original
/// data and NO partial effect from the failed step (all-or-nothing).
func checkMigrationTransactional(number: Int, url: URL) -> Bool {
    do {
        let connection = try SQLiteConnection(path: url.path)
        defer { connection.close() }
        try MigrationRunner.migrateToCurrent(connection, appBuild: "verify", timestamp: testTimestamp)
        let seededPaths = try seedFolders(connection, count: 3, prefix: "txn")
        let preCount = try Int(connection.scalarInt("SELECT count(*) FROM folders;") ?? -1)

        // A migration that makes a change, then throws mid-step.
        let throwingStep = Migration(toVersion: 2) { conn in
            _ = try seedFolders(conn, count: 2, prefix: "should-rollback")
            try conn.exec("ALTER TABLE folders ADD COLUMN doomed TEXT;")
            throw MigrationTestError()
        }
        let migrations = MigrationRunner.productionMigrations(appBuild: "verify", timestamp: testTimestamp)
            + [throwingStep]

        var threw = false
        do {
            try MigrationRunner.migrate(connection, migrations: migrations, targetVersion: 2)
        } catch {
            threw = true
        }
        guard threw else {
            printFail(number, "transactional migration: runner did not propagate the step error")
            return false
        }
        // user_version must still be 1 (the bump is inside the same rolled-back txn).
        guard try connection.userVersion() == 1 else {
            printFail(number, "transactional migration: user_version advanced despite rollback")
            return false
        }
        // Row count must be the pre-migration count (the 2 inserted rows rolled back).
        let postCount = try Int(connection.scalarInt("SELECT count(*) FROM folders;") ?? -1)
        guard postCount == preCount, postCount == seededPaths.count else {
            printFail(number, "transactional migration: folder count \(postCount) != pre \(preCount) — "
                + "partial migration leaked")
            return false
        }
        // The doomed column must NOT exist (its ADD COLUMN rolled back).
        var doomedExists = true
        do {
            _ = try connection.scalarInt("SELECT count(doomed) FROM folders;")
        } catch {
            doomedExists = false
        }
        guard !doomedExists else {
            printFail(number, "transactional migration: 'doomed' column persisted — ADD COLUMN not rolled back")
            return false
        }
        printPass(number, "migration is transactional: a throwing v1->v2 left user_version=1, "
            + "\(postCount) rows intact, and NO partial column (all-or-nothing)")
        return true
    } catch {
        printFail(number, "transactional migration threw unexpectedly: \(error)")
        return false
    }
}
