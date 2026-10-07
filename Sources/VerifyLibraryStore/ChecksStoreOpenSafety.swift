// ChecksStoreOpenSafety — S10.8 C2 store-open safety. The open path resets a library only when it
// is genuinely corrupt; a library it can't safely open or upgrade is REFUSED and left as it was,
// and every upgrade is backed up first:
//   OPEN-01 a failed migration on a healthy store is refused — the file byte-identical, nothing
//           quarantined, the backup written before the attempt — and a working build still opens it;
//   OPEN-02 an upgrade is backed up first — the backup is the store as it was (and opens as one),
//           and only the newest two backups are kept;
//   OPEN-03 no backup for a brand-new store, nor for one with nothing to migrate;
//   OPEN-04 a backup that fails refuses the upgrade — nothing migrated, nothing quarantined;
//   OPEN-05 real corruption is still quarantined — a damaged page that only `integrity_check` sees
//           (SCHEMA-5/5b cover a file that isn't a database at all).
// The newer-build refusal is SCHEMA-6 and the foreign-schema refusal FOREIGN-SCHEMA (ChecksCorruption).
//
// Each fixture is the previous release's store (the production migrator capped one step back) in
// WAL mode, as the app writes it. "Untouched" is checked on the raw bytes of the file.

import Foundation
import GRDB
import LibraryStore

// MARK: - Registration

func storeOpenSafetyCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "open01-migration-failure-refused", run: checkMigrationFailureRefused),
        CheckCase(label: "open02-backup-before-upgrade", run: checkBackupBeforeUpgrade),
        CheckCase(label: "open03-no-backup-when-current", run: checkNoBackupWhenCurrent),
        CheckCase(label: "open04-backup-failure-refuses", run: checkBackupFailureRefuses),
        CheckCase(label: "open05-damaged-page-quarantined", run: checkDamagedPageQuarantined),
    ]
}

// MARK: - Shared fixture

/// The schema the previous release wrote — what an upgrade starts from.
private let previousSchemaVersion = currentSchemaVersion - 1

/// The rows every fixture seeds, so "kept" can be counted.
private let seededFolderCount = 3

/// Build the previous release's store at `url`: written by a `DatabasePool` (WAL, like the app),
/// holding `seededFolderCount` folders. The pool closes on return, so the file is complete on disk.
private func buildPreviousReleaseStore(at url: URL) throws {
    let pool = try DatabasePool(path: url.path)
    try migrator(through: previousSchemaVersion).migrate(pool)
    try pool.write { db in _ = try seedFolders(db, count: seededFolderCount, prefix: "open") }
}

/// The schema version and folder-row count of the store file at `url`, read on a raw connection.
private func versionAndFolders(at url: URL) throws -> (version: Int, folders: Int) {
    try DatabaseQueue(path: url.path).read { db in
        try (schemaInfoVersion(db), Int.fetchOne(db, sql: "SELECT count(*) FROM folders;") ?? -1)
    }
}

// MARK: - OPEN-01 — a failed migration on a healthy store is refused, the file untouched

func checkMigrationFailureRefused(number: Int, url: URL) async -> Bool {
    do {
        try buildPreviousReleaseStore(at: url)
        let before = try Data(contentsOf: url)
        // The previous release's steps, then an upgrade step that writes and THEN fails — the shape
        // of a disk-full, I/O or foreign-key failure partway through a real migration.
        var failing = migrator(through: previousSchemaVersion)
        failing.registerMigration("open01-failing-upgrade") { db in
            _ = try seedFolders(db, count: 2, prefix: "doomed")
            throw MigrationTestError()
        }
        guard case let .openFailed(cause)? = await refusal(from: {
            try await LibraryStore(url: url, migrator: failing, stamp: testQuarantineStamp)
        }), cause is MigrationTestError else {
            printFail(number, "OPEN-01: a failed migration was not refused with .openFailed"); return false
        }
        guard try Data(contentsOf: url) == before else {
            printFail(number, "OPEN-01: the refused store's file changed"); return false
        }
        let backup = StoreBackup.backupURL(for: url, targetVersion: currentSchemaVersion, stamp: testQuarantineStamp)
        guard try strayFiles(beside: url) == [backup.lastPathComponent] else {
            try printFail(number, "OPEN-01: expected only the pre-upgrade backup beside the store, found "
                + "\(strayFiles(beside: url))"); return false
        }
        // Nothing was lost: a build whose migration works opens it with every row kept.
        let store = try await LibraryStore(url: url, migrator: fullMigrator(), stamp: "OPEN01-RETRY")
        guard await store.schemaVersion() == currentSchemaVersion,
              try await store.countRows(inTable: "folders") == seededFolderCount else {
            printFail(number, "OPEN-01: the refused store did not upgrade intact afterwards"); return false
        }
        printPass(number, "OPEN-01 a failed migration on a healthy v\(previousSchemaVersion) store is refused "
            + "(.openFailed carrying the cause): the file is byte-identical, nothing is quarantined, the backup "
            + "was written before the attempt, and a working build then upgrades it with all rows kept")
        return true
    } catch {
        printFail(number, "OPEN-01 threw: \(error)"); return false
    }
}

// MARK: - OPEN-02 — an upgrade is backed up first; only the newest two backups are kept

func checkBackupBeforeUpgrade(number: Int, url: URL) async -> Bool {
    do {
        try buildPreviousReleaseStore(at: url)
        let first = StoreBackup.backupURL(for: url, targetVersion: currentSchemaVersion, stamp: "OPEN02-1")
        do {
            let store = try await LibraryStore(url: url, migrator: fullMigrator(), stamp: "OPEN02-1")
            guard await store.schemaVersion() == currentSchemaVersion else {
                printFail(number, "OPEN-02: the store did not upgrade"); return false
            }
        }
        // The backup is the store as it was BEFORE migrating — and it opens as a store: a copy of it
        // upgrades like the original did, every row kept.
        guard try versionAndFolders(at: first) == (previousSchemaVersion, seededFolderCount) else {
            try printFail(number, "OPEN-02: the backup is not the pre-upgrade store: \(versionAndFolders(at: first))")
            return false
        }
        let restored = url.deletingPathExtension().appendingPathExtension("restored.sqlite3")
        try FileManager.default.copyItem(at: first, to: restored)
        let reopened = try await LibraryStore(url: restored, appBuild: "verify")
        guard await reopened.schemaVersion() == currentSchemaVersion,
              try await reopened.countRows(inTable: "folders") == seededFolderCount else {
            printFail(number, "OPEN-02: the backup did not open as a store"); return false
        }
        // Two more upgrades (no-op steps past the current schema): the oldest backup is pruned.
        var ahead = fullMigrator()
        for step in 2 ... 3 {
            ahead.registerMigration("open02-step-\(step)") { _ in }
            _ = try await LibraryStore(url: url, migrator: ahead, stamp: "OPEN02-\(step)")
        }
        let expected = (2 ... 3).map { step in
            StoreBackup.backupURL(for: url, targetVersion: currentSchemaVersion + step - 1, stamp: "OPEN02-\(step)")
        }
        guard try StoreBackup.backups(of: url).map(\.lastPathComponent) == expected.map(\.lastPathComponent),
              StoreBackup.keepCount == 2 else {
            try printFail(number, "OPEN-02: expected the newest two backups, found "
                + "\(StoreBackup.backups(of: url).map(\.lastPathComponent))"); return false
        }
        printPass(number, "OPEN-02 an upgrade is backed up first: \(first.lastPathComponent) holds the "
            + "v\(previousSchemaVersion) store with its rows and opens as a store; after two more upgrades only "
            + "the newest \(StoreBackup.keepCount) backups remain")
        return true
    } catch {
        printFail(number, "OPEN-02 threw: \(error)"); return false
    }
}

// MARK: - OPEN-03 — no backup for a brand-new store, nor for one with nothing to migrate

func checkNoBackupWhenCurrent(number: Int, url: URL) async -> Bool {
    do {
        do {
            let store = try await LibraryStore(url: url, appBuild: "verify")
            _ = try await store.seedFolderRow(path: "/Music/open03")
        }
        let reopened = try await LibraryStore(url: url, appBuild: "verify")
        guard try await reopened.countRows(inTable: "folders") == 1 else {
            printFail(number, "OPEN-03: the reopened store lost its row"); return false
        }
        guard try strayFiles(beside: url).isEmpty else {
            try printFail(number, "OPEN-03: files written beside a store with nothing to migrate: "
                + "\(strayFiles(beside: url))"); return false
        }
        printPass(number, "OPEN-03 no backup for a brand-new store, nor when reopening one with nothing to "
            + "migrate — nothing is written beside the store")
        return true
    } catch {
        printFail(number, "OPEN-03 threw: \(error)"); return false
    }
}

// MARK: - OPEN-04 — a backup that fails refuses the upgrade

func checkBackupFailureRefuses(number: Int, url: URL) async -> Bool {
    do {
        try buildPreviousReleaseStore(at: url)
        let before = try Data(contentsOf: url)
        // Something already sits at the backup's name (a directory), so the copy can't be moved into
        // place — a stand-in for a full disk or an unwritable folder.
        let blocked = StoreBackup.backupURL(for: url, targetVersion: currentSchemaVersion, stamp: testQuarantineStamp)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        guard case .backupFailed? = await refusal(from: {
            try await LibraryStore(url: url, migrator: fullMigrator(), stamp: testQuarantineStamp)
        }) else {
            printFail(number, "OPEN-04: a failed backup was not refused with .backupFailed"); return false
        }
        guard try Data(contentsOf: url) == before else {
            printFail(number, "OPEN-04: the store was changed (migrated without a backup?)"); return false
        }
        guard try strayFiles(beside: url) == [blocked.lastPathComponent] else {
            try printFail(number, "OPEN-04: unexpected files beside the store (a quarantine or a leftover partial "
                + "copy?): \(strayFiles(beside: url))"); return false
        }
        printPass(number, "OPEN-04 a backup that fails refuses the upgrade (.backupFailed): the "
            + "v\(previousSchemaVersion) file is byte-identical, nothing quarantined, no partial copy left")
        return true
    } catch {
        printFail(number, "OPEN-04 threw: \(error)"); return false
    }
}

// MARK: - OPEN-05 — a damaged page is still quarantined

/// Overwrite the cell pointers of the `folders` table's root page with garbage, on disk: the file
/// still opens as a database (its header is intact), but `integrity_check` fails.
private func damageFoldersRootPage(at url: URL) throws {
    let (pageSize, rootPage) = try DatabaseQueue(path: url.path).read { db in
        try (Int.fetchOne(db, sql: "PRAGMA page_size;") ?? 0,
             Int.fetchOne(db, sql: "SELECT rootpage FROM sqlite_master WHERE name = 'folders';") ?? 0)
    }
    let file = try FileHandle(forUpdating: url)
    defer { try? file.close() }
    try file.seek(toOffset: UInt64((rootPage - 1) * pageSize + 12))
    try file.write(contentsOf: Data(repeating: 0xFF, count: 200))
}

func checkDamagedPageQuarantined(number: Int, url: URL) async -> Bool {
    do {
        do {
            _ = try await LibraryStore(url: url, appBuild: "verify")
            let queue = try DatabaseQueue(path: url.path)
            try await queue.write { db in _ = try seedFolders(db, count: 400, prefix: "open05") }
        }
        try damageFoldersRootPage(at: url)
        let damaged = try Data(contentsOf: url)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard let quarantined = store.quarantinedFrom, try Data(contentsOf: quarantined) == damaged else {
            printFail(number, "OPEN-05: a file failing integrity_check was not quarantined with its bytes kept")
            return false
        }
        guard await store.schemaVersion() == currentSchemaVersion, try await store.integrityCheck(),
              try await store.countRows(inTable: "folders") == 0 else {
            printFail(number, "OPEN-05: the rebuilt store is not a fresh, valid store"); return false
        }
        printPass(number, "OPEN-05 a damaged page (header intact, so the file opens) fails the integrity_check "
            + "the open path runs before writing, and is still quarantined — bytes kept as "
            + "\(quarantined.lastPathComponent) — and rebuilt fresh at v\(currentSchemaVersion)")
        return true
    } catch {
        printFail(number, "OPEN-05 threw: \(error)"); return false
    }
}
