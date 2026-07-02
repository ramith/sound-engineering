// ChecksCorruption — SCHEMA-5 (corruption→quarantine+rebuild), SCHEMA-6
// (downgrade guard), and RESTART durability. Companion to Checks.swift / main.swift.

import Foundation
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

/// SCHEMA-6: a store whose `user_version` is NEWER than the app quarantines +
/// rebuilds rather than crashing or running an unknown-newer schema. First the
/// runner is asserted to throw `.schemaTooNew`; then the actor is asserted to
/// recover by quarantine + rebuild (defined, non-crashing behaviour).
func checkDowngradeGuard(number: Int, url: URL) async -> Bool {
    do {
        // 1. Build a valid v1 store, then force its user_version far into the future.
        do {
            let connection = try SQLiteConnection(path: url.path)
            defer { connection.close() }
            try MigrationRunner.migrateToCurrent(connection, appBuild: "verify", timestamp: testTimestamp)
            _ = try seedFolders(connection, count: 2, prefix: "future")
            try connection.setUserVersion(currentSchemaVersion + 99)
        }

        // 2. The runner MUST refuse (schemaTooNew), never silently proceed.
        var runnerRefused = false
        do {
            let connection = try SQLiteConnection(path: url.path)
            defer { connection.close() }
            try MigrationRunner.migrateToCurrent(connection, appBuild: "verify", timestamp: testTimestamp)
        } catch let error as SQLiteError {
            if case .schemaTooNew = error { runnerRefused = true }
        }
        guard runnerRefused else {
            printFail(number, "downgrade guard: runner did not throw schemaTooNew for a newer store")
            return false
        }

        // 3. The actor MUST recover (quarantine + rebuild) — defined, non-crashing.
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let version = await store.schemaVersion()
        guard version == currentSchemaVersion, try await store.integrityCheck() else {
            printFail(number, "downgrade guard: actor did not rebuild to v\(currentSchemaVersion) "
                + "(got v\(version))")
            return false
        }
        // The rebuilt store is fresh (only the sentinel artist; the future rows are
        // quarantined away, not silently carried into an unknown schema).
        let folderCount = try await store.countRows(inTable: "folders")
        guard folderCount == 0 else {
            printFail(number, "downgrade guard: rebuilt store unexpectedly has \(folderCount) folders")
            return false
        }
        printPass(number, "downgrade guard: newer user_version (v\(currentSchemaVersion + 99)) → runner "
            + "throws schemaTooNew AND the actor quarantines + rebuilds a fresh v\(version); no crash")
        return true
    } catch {
        printFail(number, "downgrade guard threw: \(error)")
        return false
    }
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
