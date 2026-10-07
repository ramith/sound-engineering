// ChecksCorruption — SCHEMA-5 (corruption→quarantine+rebuild), SCHEMA-6
// (downgrade guard → refused), and RESTART durability. Companion to Checks.swift / main.swift.

import Foundation
import GRDB
import LibraryStore

// MARK: - SCHEMA-5 — corrupt file → quarantine (+ sidecars) + rebuild

/// SCHEMA-5: a corrupt store file — WITH live `-wal`/`-shm` sidecars present — is
/// quarantined (main file + both sidecars renamed `library.corrupt-<stamp>.…`) and
/// a fresh, valid store is rebuilt in its place, with no crash. The quarantined
/// file is preserved (never deleted).
func checkCorruptQuarantineRebuild(number: Int, url: URL) async -> Bool {
    let fileManager = FileManager.default
    // SQLite WAL sidecars are the store filename with -wal / -shm appended to the
    // whole last path component (library.sqlite3-wal), NOT a new path extension.
    let sidecarBase = url.deletingLastPathComponent()
    let walURL = sidecarBase.appendingPathComponent(url.lastPathComponent + "-wal")
    let shmURL = sidecarBase.appendingPathComponent(url.lastPathComponent + "-shm")
    do {
        // 1. Write garbage bytes as the "database" plus live -wal/-shm sidecars.
        let garbage = Data("this is not a sqlite database — truncated garbage header".utf8)
        try garbage.write(to: url)
        try Data("live-wal-bytes".utf8).write(to: walURL)
        try Data("live-shm-bytes".utf8).write(to: shmURL)

        // 2. Predict the quarantine destinations for the fixed test stamp.
        let quarantinedMain = StoreQuarantine.quarantineURL(for: url, stamp: testQuarantineStamp)
        let quarantinedWal = StoreQuarantine.quarantineURL(for: walURL, stamp: testQuarantineStamp)
        let quarantinedShm = StoreQuarantine.quarantineURL(for: shmURL, stamp: testQuarantineStamp)

        // 3. Directly drive quarantine with the injectable stamp (deterministic
        //    filenames), then rebuild — mirroring the actor's repair path but with a
        //    known stamp so the exact filenames are assertable.
        let moved = try StoreQuarantine.quarantine(storeURL: url, stamp: testQuarantineStamp)
        guard moved.count == 3 else {
            printFail(number, "corrupt quarantine: expected 3 files moved (main+wal+shm), moved \(moved.count)")
            return false
        }
        for destination in [quarantinedMain, quarantinedWal, quarantinedShm] {
            guard fileManager.fileExists(atPath: destination.path) else {
                printFail(number, "corrupt quarantine: expected quarantined file missing: "
                    + destination.lastPathComponent)
                return false
            }
        }
        // The originals must be gone (renamed away, not copied).
        for original in [url, walURL, shmURL] where fileManager.fileExists(atPath: original.path) {
            printFail(number, "corrupt quarantine: original still present after quarantine: "
                + original.lastPathComponent)
            return false
        }

        // 4. Rebuild fresh at the original URL via the actor and assert it is valid.
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let version = await store.schemaVersion()
        guard version == currentSchemaVersion, try await store.integrityCheck() else {
            printFail(number, "corrupt quarantine: rebuilt store not valid (v\(version))")
            return false
        }
        // 5. The quarantined corrupt bytes are preserved, not deleted.
        let preserved = try (Data(contentsOf: quarantinedMain)) == garbage
        guard preserved else {
            printFail(number, "corrupt quarantine: quarantined file content not preserved")
            return false
        }
        printPass(number, "corrupt file (+ live -wal/-shm) quarantined to "
            + "\(quarantinedMain.lastPathComponent) (+2 sidecars) and a fresh v\(version) store rebuilt; "
            + "no crash; corrupt bytes preserved")
        return true
    } catch {
        printFail(number, "corrupt quarantine threw: \(error)")
        return false
    }
}

/// SCHEMA-5b: prove the ACTOR's own repair path handles a corrupt file end to end
/// (no manual quarantine call) — open a store, corrupt the file underneath a fresh
/// open, and confirm the actor quarantines + rebuilds automatically.
func checkActorAutoRepair(number: Int, url: URL) async -> Bool {
    let fileManager = FileManager.default
    do {
        // Write a corrupt (non-SQLite) file directly.
        try Data(repeating: 0xAB, count: 4096).write(to: url)
        // Opening via the actor must NOT crash and must produce a valid store.
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let version = await store.schemaVersion()
        guard version == currentSchemaVersion, try await store.integrityCheck() else {
            printFail(number, "actor auto-repair: store not valid after opening a corrupt file")
            return false
        }
        // A quarantine file for THIS store's stem (with the app's default stamp)
        // must exist alongside. Filter on the store stem so other cases' quarantine
        // artifacts in the shared test-data dir cannot mask a genuine failure here.
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
        let quarantined = contents.filter { $0.hasPrefix(stem) && $0.contains(".corrupt-") }
        guard !quarantined.isEmpty else {
            printFail(number, "actor auto-repair: no quarantine file produced by the actor for \(stem)")
            return false
        }
        printPass(number, "actor auto-repair: opening a corrupt file quarantined it "
            + "(\(quarantined.count) file(s)) and rebuilt a valid v\(version) store — no crash")
        return true
    } catch {
        printFail(number, "actor auto-repair threw: \(error)")
        return false
    }
}

// MARK: - SCHEMA-6 — downgrade guard

/// SCHEMA-6: a store written by a NEWER build is REFUSED and left as it was (S10.8 C2 — it used to be
/// quarantined + rebuilt, so an older build opened an empty library). GRDB's `DatabaseMigrator`
/// records applied migrations in `grdb_migrations`; the open path's `hasBeenSuperseded` is true when
/// the file carries one this build does not know. We inject a future migration id and assert the
/// open throws `.newerVersion`, the file is byte-identical, and nothing is quarantined or backed up.
func checkDowngradeGuard(number: Int, url: URL) async -> Bool {
    do {
        // 1. Build a valid store + seed rows, then INJECT a future migration id into
        //    grdb_migrations (an applied id the app's migrator does not know).
        do {
            let store = try await LibraryStore(url: url, appBuild: "verify")
            _ = try await store.seedFolderRow(path: "/Music/future-A")
            _ = try await store.seedFolderRow(path: "/Music/future-B")
        }
        do {
            let tamper = try DatabaseQueue(path: url.path)
            try await tamper.write { db in
                try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v9999-from-the-future');")
            }
        }
        let before = try Data(contentsOf: url)

        // 2. Reopening is REFUSED — no store, never a quarantine or a rebuild — and the file is
        //    byte-identical, so the newer build still opens it with every row.
        guard case .newerVersion? = await refusal(from: { try await LibraryStore(url: url, appBuild: "verify") }) else {
            printFail(number, "downgrade guard: a store from a newer build was not refused with .newerVersion")
            return false
        }
        guard try Data(contentsOf: url) == before else {
            printFail(number, "downgrade guard: the refused store's file changed"); return false
        }
        guard try strayFiles(beside: url).isEmpty else {
            try printFail(number, "downgrade guard: files written beside the refused store: "
                + "\(strayFiles(beside: url))"); return false
        }
        guard try await newerWritesOnlyInWALRefusedUntouched(beside: url, number: number) else { return false }
        printPass(number, "downgrade guard: an unknown-newer migration id → hasBeenSuperseded fires and the "
            + "open is REFUSED (.newerVersion): the file is byte-identical, nothing quarantined, backed up or "
            + "rebuilt; no crash — and the same when the newer build's writes are still only in the WAL (a "
            + "crash): the refusal's look-first connection does not checkpoint them into the main file")
        return true
    } catch {
        printFail(number, "downgrade guard threw: \(error)")
        return false
    }
}

/// The newer build's migration id (and a row) still ONLY in the WAL — the newer build crashed after
/// writing. The refusal must still leave the main file byte-identical and the WAL holding them
/// (S10.8 C2 final round): closing the look-first connection must not checkpoint.
private func newerWritesOnlyInWALRefusedUntouched(beside url: URL, number: Int) async throws -> Bool {
    let directory = url.deletingLastPathComponent()
        .appendingPathComponent("schema6-hot-wal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.sqlite3")
    let crashed = directory.appendingPathComponent("library.sqlite3")
    _ = try await LibraryStore(url: source, appBuild: "verify")
    try copyWithHotWAL(from: source, to: crashed) { db in
        try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v9999-from-the-future');")
        try db.execute(sql: "INSERT INTO folders(path, is_root) VALUES ('/Music/future-wal', 1);")
    }
    let before = try Data(contentsOf: crashed)
    let walBefore = walSize(of: crashed)
    guard walBefore > 0 else { printFail(number, "downgrade guard: the hot-WAL fixture has no WAL"); return false }
    guard case .newerVersion? = await refusal(from: { try await LibraryStore(url: crashed, appBuild: "verify") }) else {
        printFail(number, "downgrade guard: a newer store whose id is only in the WAL was not refused"); return false
    }
    guard try Data(contentsOf: crashed) == before, walSize(of: crashed) == walBefore else {
        printFail(number, "downgrade guard: refusing a store with a hot WAL changed its main file (checkpoint on "
            + "close) or its WAL"); return false
    }
    return true
}

// MARK: - RESTART durability

/// RESTART: seed rows through one store instance, drop it (closing the connection
/// + flushing the WAL), then open a SECOND instance on the same file and confirm
/// the rows are present — proving durability across a store restart. `swift run`
/// also exposes an explicit two-invocation mode (see main.swift), but this
/// in-process reopen is a genuine on-disk round-trip (a fresh connection reads the
/// committed WAL), so it stands alone as the durability proof.
func checkRestartDurability(number: Int, url: URL) async -> Bool {
    do {
        let seededPaths: [String]
        // Write phase — a scoped store instance so it is fully released (connection
        // closed on deinit, WAL committed) before the read phase opens a new one.
        do {
            let writeStore = try await LibraryStore(url: url, appBuild: "verify")
            _ = try await writeStore.seedFolderRow(path: "/Music/Durable-A")
            _ = try await writeStore.seedFolderRow(path: "/Music/Durable-B")
            _ = try await writeStore.seedFolderRow(path: "/Music/Durable-C")
            seededPaths = ["/Music/Durable-A", "/Music/Durable-B", "/Music/Durable-C"]
            let writeCount = try await writeStore.countRows(inTable: "folders")
            guard writeCount == seededPaths.count else {
                printFail(number, "restart durability: write phase counted \(writeCount) folders, "
                    + "expected \(seededPaths.count)")
                return false
            }
        }

        // Read phase — a brand-new store instance on the same file.
        let readStore = try await LibraryStore(url: url, appBuild: "verify")
        let readCount = try await readStore.countRows(inTable: "folders")
        guard readCount == seededPaths.count else {
            printFail(number, "restart durability: reopened store counted \(readCount) folders, "
                + "expected \(seededPaths.count) — data did NOT survive restart")
            return false
        }
        guard await readStore.schemaVersion() == currentSchemaVersion,
              try await readStore.integrityCheck() else {
            printFail(number, "restart durability: reopened store not valid")
            return false
        }
        printPass(number, "restart durability: \(seededPaths.count) rows written, store closed + "
            + "reopened (fresh connection), all \(readCount) rows present + integrity ok")
        return true
    } catch {
        printFail(number, "restart durability threw: \(error)")
        return false
    }
}

// MARK: - ADDITIVE — an appended migration PRESERVES user data (eraseDatabaseOnSchemaChange = false)

/// ADDITIVE: the store sets `eraseDatabaseOnSchemaChange = false` (S10.3) because it holds
/// non-rebuildable USER data — playlists/entries + the track user-state columns
/// (`play_count`/`loved`/`rating`/`last_played`/`frecency_*`). So a schema change must be an
/// APPENDED migration that PRESERVES existing rows, never a wipe-and-recreate (a break-it pass
/// showed the old erase-on-schema-change rule silently destroyed that user data). Proven directly
/// on a GRDB `DatabaseMigrator` configured like production: seed under migration `m1`, then reopen
/// with `m1` FROZEN plus an APPENDED `m2` — the seeded row SURVIVES and `m2`'s new table appears.
/// Locks the additive-only posture against a future regression that flips the flag back to `true`.
func checkAdditiveMigrationPreservesData(number: Int, url: URL) async -> Bool {
    func migrator(withM2: Bool) -> DatabaseMigrator {
        var mig = DatabaseMigrator()
        mig.eraseDatabaseOnSchemaChange = false
        mig.registerMigration("m1") { db in
            try db.execute(sql: "CREATE TABLE demo(id INTEGER PRIMARY KEY, v TEXT);")
            try db.execute(sql: "INSERT INTO demo(v) VALUES ('kept');")
        }
        if withM2 {
            mig.registerMigration("m2") { db in
                try db.execute(sql: "CREATE TABLE demo2(id INTEGER PRIMARY KEY);")
            }
        }
        return mig
    }
    do {
        do {
            let queue = try DatabaseQueue(path: url.path)
            try migrator(withM2: false).migrate(queue)
        }
        // Reopen: `m1` FROZEN + an APPENDED `m2`. With erase=false, GRDB runs only the new `m2`,
        // leaving `m1`'s seeded rows intact — the opposite of the former drop-and-recreate.
        let queue = try DatabaseQueue(path: url.path)
        try migrator(withM2: true).migrate(queue)
        let kept = try await queue.read { db in try String.fetchOne(db, sql: "SELECT v FROM demo LIMIT 1;") }
        let hasDemo2 = try await queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='demo2';") ?? false
        }
        guard kept == "kept", hasDemo2 else {
            printFail(number, "additive-preserve: appended migration wiped or skipped "
                + "(kept=\(kept ?? "nil"), demo2=\(hasDemo2))")
            return false
        }
        printPass(number, "additive-preserve: appending a migration PRESERVES seeded user data and runs the "
            + "new migration (erase=false) — locks the additive-only posture")
        return true
    } catch {
        printFail(number, "additive-preserve threw: \(error)")
        return false
    }
}

// MARK: - FOREIGN-SCHEMA — a store with app tables but no grdb_migrations records → refused

/// FOREIGN-SCHEMA REFUSED: a pre-existing store whose app tables are present but NOT recorded in
/// GRDB's `grdb_migrations` (a store from the prior, `user_version`-based migration scheme). GRDB's
/// migrator re-runs `v1-create-all` and collides with the existing tables (`CREATE TABLE … already
/// exists`). That used to quarantine + rebuild; since S10.8 C2 only real corruption does, so this — a
/// real migration failure on an intact file — is REFUSED (`.openFailed`): the file byte-identical,
/// nothing quarantined. Only the pre-upgrade backup, written before the attempt, sits beside it.
func checkForeignSchemaRefused(number: Int, url: URL) async -> Bool {
    do {
        // 1. Build a valid store + seed a row, then ERASE grdb_migrations so the app tables exist
        //    with NO recorded migrations — the exact shape a pre-GRDB store presents to the migrator.
        do {
            let store = try await LibraryStore(url: url, appBuild: "verify")
            _ = try await store.seedFolderRow(path: "/Music/foreign-A")
        }
        do {
            let tamper = try DatabaseQueue(path: url.path)
            try await tamper.write { db in try db.execute(sql: "DELETE FROM grdb_migrations;") }
        }
        let before = try Data(contentsOf: url)

        // 2. Reopening is REFUSED — migrate re-runs v1, the CREATE collides and rolls back.
        guard case .openFailed? = await refusal(from: { try await LibraryStore(url: url, appBuild: "verify") }) else {
            printFail(number, "foreign-schema: the colliding migration was not refused with .openFailed")
            return false
        }
        guard try Data(contentsOf: url) == before else {
            printFail(number, "foreign-schema: the refused store's file changed"); return false
        }
        let backups = try StoreBackup.backups(of: url).map(\.lastPathComponent)
        guard backups.count == 1, try strayFiles(beside: url) == backups else {
            try printFail(number, "foreign-schema: expected only the pre-upgrade backup beside the store, found "
                + "\(strayFiles(beside: url))"); return false
        }
        printPass(number, "foreign-schema refused: a store with app tables but NO grdb_migrations records "
            + "(a pre-GRDB / foreign-migration file) is refused (.openFailed) — byte-identical, nothing "
            + "quarantined, the pre-upgrade backup beside it")
        return true
    } catch {
        printFail(number, "foreign-schema threw: \(error)")
        return false
    }
}
