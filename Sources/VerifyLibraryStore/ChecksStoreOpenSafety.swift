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
//           (SCHEMA-5/5b cover a file that isn't a database at all);
//   OPEN-06 a store an UNFINISHED test build migrated to v7 (v7 was amended in place — the first C2
//           build's shape, and the first fix round's) is refused (.unfinishedTestVersion), byte-identical
//           even with writes still in its WAL; a store this build migrated passes the same shape check.
// OPEN-02 also proves a backup a crash left half-written (`.partial` + journal) is cleared.
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
        CheckCase(label: "open06-unfinished-v7-refused", run: checkUnfinishedV7Refused),
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
        // What a crash mid-backup leaves: a half-written copy and its journal. The next backup clears them.
        let stale = StoreBackup.backupURL(for: url, targetVersion: currentSchemaVersion, stamp: "OPEN02-0")
            .appendingPathExtension("partial")
        try Data("half a copy".utf8).write(to: stale)
        try Data().write(to: URL(fileURLWithPath: stale.path + "-journal"))
        do {
            let store = try await LibraryStore(url: url, migrator: fullMigrator(), stamp: "OPEN02-1")
            guard await store.schemaVersion() == currentSchemaVersion else {
                printFail(number, "OPEN-02: the store did not upgrade"); return false
            }
        }
        guard !FileManager.default.fileExists(atPath: stale.path),
              !FileManager.default.fileExists(atPath: stale.path + "-journal") else {
            printFail(number, "OPEN-02: a stale .partial backup (or its journal) survived the next backup")
            return false
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
            + "v\(previousSchemaVersion) store with its rows and opens as a store; a half-written backup a crash "
            + "left (.partial + journal) is cleared; after two more upgrades only the newest "
            + "\(StoreBackup.keepCount) backups remain")
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

// MARK: - OPEN-06 — a store an unfinished test build migrated to v7 is refused, untouched

/// The v7 the FIRST C2 build ran (858db30), on top of a v6 store: the year still in the album key, no
/// `regroup_owed`, no `edition_year`. (Its data backfill is left out — only the shape matters here.)
private let firstBuildV7Statements = [
    "ALTER TABLE tracks ADD COLUMN album_title TEXT;",
    "ALTER TABLE tracks ADD COLUMN album_artist_tag TEXT;",
    "ALTER TABLE tracks ADD COLUMN compilation INTEGER NOT NULL DEFAULT 0;",
    "CREATE INDEX idx_tracks_album_title ON tracks(album_title);",
    """
    CREATE TABLE albums_v7 (id INTEGER PRIMARY KEY, title TEXT NOT NULL,
        album_artist_id INTEGER NOT NULL DEFAULT 0 REFERENCES artists(id) ON DELETE SET DEFAULT,
        year INTEGER NOT NULL DEFAULT 0, artwork_key TEXT REFERENCES artwork(content_hash) ON DELETE SET NULL,
        folder_key TEXT NOT NULL DEFAULT '');
    """,
    """
    INSERT INTO albums_v7(id, title, album_artist_id, year, artwork_key)
    SELECT id, title, album_artist_id, year, artwork_key FROM albums;
    """,
    "DROP TABLE albums;",
    "ALTER TABLE albums_v7 RENAME TO albums;",
    "CREATE UNIQUE INDEX idx_albums_key ON albums(title, album_artist_id, year, folder_key);",
    "CREATE INDEX idx_albums_artist ON albums(album_artist_id);",
    "CREATE INDEX idx_albums_year ON albums(year);",
    "ALTER TABLE schema_info ADD COLUMN derived_version INTEGER NOT NULL DEFAULT 0;",
]

/// What the FIRST fix round's v7 added on top: `regroup_owed`, and the key without the year (but
/// without `edition_year` either).
private let firstFixRoundV7Statements = [
    "ALTER TABLE schema_info ADD COLUMN regroup_owed INTEGER NOT NULL DEFAULT 0;",
    "DROP INDEX idx_albums_key;",
    "CREATE UNIQUE INDEX idx_albums_key ON albums(title, album_artist_id, folder_key);",
]

/// Build, at `url`, a WAL store an unfinished test build migrated to v7: the previous release's
/// store with folders and a playlist, then `statements` as that build's v7, recorded as applied.
private func buildUnfinishedV7Store(at url: URL, statements: [String]) throws {
    var config = Configuration()
    config.foreignKeysEnabled = false // a table rebuild, as the migrator runs it
    let pool = try DatabasePool(path: url.path, configuration: config)
    try migrator(through: 6).migrate(pool)
    try pool.write { db in
        _ = try seedFolders(db, count: seededFolderCount, prefix: "open06")
        try db.execute(sql: "INSERT INTO playlists(name, is_builtin, created_at) VALUES ('Kept', 0, 1);")
        for statement in statements {
            try db.execute(sql: statement)
        }
        try db.execute(sql: "UPDATE schema_info SET version = 7 WHERE id = 1;")
        try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES (?);", arguments: [Schema.MigrationID.v7])
    }
    try pool.close()
}

func checkUnfinishedV7Refused(number: Int, url: URL) async -> Bool {
    let shapes = [("the first C2 build", firstBuildV7Statements),
                  ("the first fix round", firstBuildV7Statements + firstFixRoundV7Statements)]
    do {
        for (index, (name, statements)) in shapes.enumerated() {
            let directory = url.deletingLastPathComponent()
                .appendingPathComponent("open06-\(index)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let built = directory.appendingPathComponent("built.sqlite3")
            let store = directory.appendingPathComponent("library.sqlite3")
            try buildUnfinishedV7Store(at: built, statements: statements)
            // That build crashed with a write still in its WAL.
            try copyWithHotWAL(from: built, to: store) { db in
                try db.execute(sql: "INSERT INTO folders(path, is_root) VALUES ('/Music/open06-wal', 1);")
            }
            let before = try Data(contentsOf: store)
            let walBefore = walSize(of: store)
            let refused = await refusal(from: { try await LibraryStore(url: store, appBuild: "verify") })
            guard case .unfinishedTestVersion? = refused else {
                printFail(number, "OPEN-06: a store \(name) migrated to v7 was not refused (.unfinishedTestVersion)")
                return false
            }
            guard walBefore > 0, try Data(contentsOf: store) == before, walSize(of: store) == walBefore,
                  try strayFiles(beside: store).isEmpty else {
                try printFail(number, "OPEN-06: refusing \(name)'s store changed its file or WAL, or wrote beside "
                    + "it: \(strayFiles(beside: store))"); return false
            }
        }
        // This build's own v7 passes the same check: a previous-release store upgrades and opens.
        try buildPreviousReleaseStore(at: url)
        let upgraded = try await LibraryStore(url: url, migrator: fullMigrator(), stamp: "OPEN06")
        guard await upgraded.schemaVersion() == currentSchemaVersion else {
            printFail(number, "OPEN-06: a store this build migrated to v7 did not open"); return false
        }
        printPass(number, "OPEN-06 a store an unfinished test build migrated to v7 (the first C2 build's shape, "
            + "and the first fix round's) is refused (.unfinishedTestVersion): the file and its WAL — still "
            + "holding a crash's write — are byte-identical, nothing is written beside it; a store this build "
            + "migrates passes the same shape check")
        return true
    } catch {
        printFail(number, "OPEN-06 threw: \(error)"); return false
    }
}
