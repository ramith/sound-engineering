// Checks — the S8.1a schema/migration/corruption/durability verification cases.
//
// Companion to main.swift (which owns the top-level driver + `fail`). Each check
// returns a `Bool` (true = PASS) and prints a numbered PASS/FAIL line in the
// VerifyAUGraph idiom. All temp databases live under `test-data/` (never /tmp),
// are UUID-unique, and are cleaned up by the driver on overall success (kept on
// failure for post-mortem).
//
// The harness drives the store's persistence layer directly (GRDB `DatabaseQueue` +
// `DatabaseMigrator` built from the production `Schema` migration bodies) to prove the
// migration mechanics — exactly the "let the harness use the DB layer directly" path the
// design permits. The `LibraryStore` end-to-end open/repair + durability paths are
// exercised through its public API. GRDB tracks applied migrations in its own
// `grdb_migrations` table; `schema_info.version` is our app-facing provenance mirror.

import Foundation
import GRDB
import LibraryStore

// MARK: - Shared fixture helpers

/// A fixed, deterministic quarantine stamp so SCHEMA-5 can assert the resulting
/// filenames exactly (the design requires the stamp be injectable/testable).
let testQuarantineStamp = "TESTSTAMP-00000000"

/// A fixed timestamp for migrations so provenance rows are deterministic.
let testTimestamp: Int64 = 1_700_000_000

/// Seed `count` `folders` rows on an open `Database` (a persistent, FK-free fixture usable
/// to prove migration/restart preserves data). Returns the paths.
@discardableResult
func seedFolders(_ db: Database, count: Int, prefix: String) throws -> [String] {
    var paths: [String] = []
    for index in 0 ..< count {
        let path = "/Music/\(prefix)-\(index)"
        try db.execute(sql: "INSERT INTO folders(path, is_root) VALUES (?, 1);", arguments: [path])
        paths.append(path)
    }
    return paths
}

/// A `DatabaseMigrator` with ONLY the v1 (create-all) step — used by the SCHEMA-3/4
/// migration-mechanics checks to build a genuine v1 store, so they can then exercise the
/// REAL v1→v2 (built from the production `Schema` migration bodies).
func v1OnlyMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration(Schema.MigrationID.v1) { db in
        try Schema.migrateV0toV1(db, appBuild: "verify", timestamp: testTimestamp)
    }
    return migrator
}

/// The full v1→v2 migrator (create-all + the real FTS5 step) from the production `Schema`
/// bodies. Uses the SAME `Schema.MigrationID` identifiers as `LibraryStore.makeMigrator`, so a
/// v1 store it (or `v1OnlyMigrator`) builds can be handed to `LibraryStore` without tripping the
/// `hasBeenSuperseded` downgrade guard.
func fullMigrator() -> DatabaseMigrator {
    var migrator = v1OnlyMigrator()
    migrator.registerMigration(Schema.MigrationID.v2) { db in
        try Schema.migrateV1toV2(db, appBuild: "verify", timestamp: testTimestamp)
    }
    migrator.registerMigration(Schema.MigrationID.v3) { db in
        try Schema.migrateV2toV3(db, appBuild: "verify", timestamp: testTimestamp)
    }
    migrator.registerMigration(Schema.MigrationID.v4) { db in
        try Schema.migrateV3toV4(db, appBuild: "verify", timestamp: testTimestamp)
    }
    return migrator
}

/// The app-facing schema version from `schema_info` (our provenance mirror; GRDB keeps the
/// authoritative applied-migration state in `grdb_migrations`).
func schemaInfoVersion(_ db: Database) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT version FROM schema_info WHERE id = 1;") ?? 0
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

// MARK: - SCHEMA-3 — the REAL v1→v2 migration preserves data + creates FTS

/// SCHEMA-3: build a genuine v1 store, seed rows, then run the REAL production
/// v1→v2 migration (S9.2 FTS5) and assert EVERY row survived AND `tracks_fts` was
/// created. (Rich track backfill correctness is FTS-MIG1/MIG2 in ChecksSearch.)
func checkMigrationPreservesData(number: Int, url: URL) -> Bool {
    do {
        // Bring an empty DB to v1 ONLY (so the real v1→v2 below is what we exercise), seed rows.
        let seededPaths: [String]
        do {
            let queue = try DatabaseQueue(path: url.path)
            try v1OnlyMigrator().migrate(queue)
            seededPaths = try queue.write { db in try seedFolders(db, count: 5, prefix: "v1seed") }
            let version = try queue.read { db in try schemaInfoVersion(db) }
            guard version == 1 else {
                printFail(number, "migration preserves data: pre-migration version \(version) != 1")
                return false
            }
        }

        // Reopen and run the REAL production v1 → v2 (FTS5 table + backfill).
        let queue = try DatabaseQueue(path: url.path)
        try fullMigrator().migrate(queue)

        let (version, folderCount, ftsExists) = try queue.read { db in
            try (schemaInfoVersion(db),
                 Int.fetchOne(db, sql: "SELECT count(*) FROM folders;") ?? -1,
                 Int.fetchOne(
                     db, sql: "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'tracks_fts';"
                 ) ?? 0)
        }
        guard version == currentSchemaVersion else {
            printFail(number, "migration preserves data: post-migration version \(version) != \(currentSchemaVersion)")
            return false
        }
        guard folderCount == seededPaths.count else {
            printFail(number, "migration preserves data: \(folderCount) folders survived, "
                + "expected \(seededPaths.count)")
            return false
        }
        guard ftsExists == 1 else {
            printFail(number, "migration preserves data: tracks_fts not created by the real v1->v2")
            return false
        }
        printPass(number, "migrator preserves data: the REAL v1->v2 kept all "
            + "\(folderCount) seeded rows and created tracks_fts")
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
        let queue = try DatabaseQueue(path: url.path)
        // Build a genuine v1 store (NOT v2 — we test a throwing v1→v2 below).
        try v1OnlyMigrator().migrate(queue)
        let seededPaths = try queue.write { db in try seedFolders(db, count: 3, prefix: "txn") }
        let preCount = try queue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM folders;") ?? -1 }

        // A v1→v2 migration that makes a change, then throws mid-step. GRDB runs each
        // migration in its own transaction, so the whole step must roll back atomically.
        var throwingMigrator = v1OnlyMigrator()
        throwingMigrator.registerMigration(Schema.MigrationID.v2) { db in
            _ = try seedFolders(db, count: 2, prefix: "should-rollback")
            try db.execute(sql: "ALTER TABLE folders ADD COLUMN doomed TEXT;")
            throw MigrationTestError()
        }

        var threw = false
        do {
            try throwingMigrator.migrate(queue)
        } catch {
            threw = true
        }
        guard threw else {
            printFail(number, "transactional migration: migrator did not propagate the step error")
            return false
        }
        // schema_info.version must still be 1 (the v2 provenance write is inside the rolled-back txn).
        let version = try queue.read { db in try schemaInfoVersion(db) }
        guard version == 1 else {
            printFail(number, "transactional migration: schema_info.version advanced to \(version) despite rollback")
            return false
        }
        // Row count must be the pre-migration count (the 2 inserted rows rolled back).
        let postCount = try queue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM folders;") ?? -1 }
        guard postCount == preCount, postCount == seededPaths.count else {
            printFail(number, "transactional migration: folder count \(postCount) != pre \(preCount) — "
                + "partial migration leaked")
            return false
        }
        // The doomed column must NOT exist (its ADD COLUMN rolled back).
        var doomedExists = true
        do {
            _ = try queue.read { db in try Int.fetchOne(db, sql: "SELECT count(doomed) FROM folders;") }
        } catch {
            doomedExists = false
        }
        guard !doomedExists else {
            printFail(number, "transactional migration: 'doomed' column persisted — ADD COLUMN not rolled back")
            return false
        }
        printPass(number, "migration is transactional: a throwing v1->v2 left schema_info.version=1, "
            + "\(postCount) rows intact, and NO partial column (all-or-nothing)")
        return true
    } catch {
        printFail(number, "transactional migration threw unexpectedly: \(error)")
        return false
    }
}
