// LibraryStore+Open — the open path: look before writing, refuse rather than reset (S10.8 C2).
//
// The store file holds the user's playlists and play history, so the open path resets a file only
// when it is genuinely damaged. An EXISTING file is first looked at on one plain connection that
// only reads — a `DatabasePool` writes as it opens (its WAL set-up), so the pool waits until the
// file is known good:
//   • damaged — SQLITE_CORRUPT / SQLITE_NOTADB, or `integrity_check` fails → quarantine (renamed
//     aside, never deleted) and rebuild fresh; the app names the saved file.
//   • written by a NEWER build (a migration id this build doesn't know) → refuse, the file untouched;
//     the newer build still opens it.
//   • behind (migrations pending) → migrate on that same connection.
//   • any other failure on an intact file — disk full mid-migration, an I/O error, a busy timeout, a
//     foreign-key violation — → refuse. Each migration step is one transaction, so the failed step
//     rolls back (any step before it stays applied — each leaves a whole store).
// A refusal throws `StoreOpenRefusal`: the app runs without the store (the additive seam) and says why.

import Foundation
import GRDB

/// Why the store refused to open an existing library. The file is never reset or moved — it keeps
/// all its data where it is.
public enum StoreOpenRefusal: Error {
    /// A newer build last wrote this library: it records a migration this build doesn't know.
    case newerVersion
    /// The library is intact but could not be opened or upgraded.
    case openFailed(any Error)
}

extension LibraryStore {
    /// Result of opening/migrating a store: the writer, the schema version reached, and — when a
    /// pre-existing corrupt file was quarantined + rebuilt — the quarantined path (else nil). A
    /// struct (not a 3-tuple) to stay within the large-tuple lint bound.
    struct OpenedStore {
        let writer: any DatabaseWriter
        let version: Int
        let quarantinedFrom: URL?
    }

    /// `integrity_check` did not answer "ok" — the one corruption SQLite reports as data, not an error.
    private struct FailedIntegrityCheck: Error {}

    /// Read the schema version back from `schema_info` (0 on a fresh, unwritten store).
    private static let selectSchemaVersionSQL = "SELECT version FROM schema_info WHERE id = 1;"

    /// The GRDB `Configuration` shared by every store connection: WAL is implied by
    /// `DatabasePool`; `foreign_keys` ON (design §5); a 5 s busy timeout so a writer
    /// waits under contention rather than failing with `SQLITE_BUSY` immediately.
    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(5)
        return config
    }

    /// Open + migrate the store at `url`: an in-memory or brand-new store directly; an existing
    /// file through `upgradeInPlace` first, quarantined only when it is corrupt.
    static func openMigratingAndRepairing(url: URL, migrator: DatabaseMigrator, stamp: String) throws -> OpenedStore {
        // In-memory stores can't be corrupt/quarantined; open + migrate directly.
        if url.path == ":memory:" || url.absoluteString == "file::memory:" {
            let queue = try DatabaseQueue(configuration: makeConfiguration())
            try migrator.migrate(queue)
            return try OpenedStore(writer: queue, version: readSchemaVersion(queue), quarantinedFrom: nil)
        }
        // A brand-new file holds nothing to protect: no backup, and a failure is a genuine bug.
        guard FileManager.default.fileExists(atPath: url.path) else {
            return try openPool(url: url, migrator: migrator, quarantinedFrom: nil)
        }
        do {
            try upgradeInPlace(url: url, migrator: migrator)
            return try openPool(url: url, migrator: migrator, quarantinedFrom: nil)
        } catch let error where isCorruption(error) {
            // Damaged beyond use. Quarantine it (+ sidecars) and rebuild fresh — the DERIVED cache
            // re-scans, but the file ALSO held user data a rebuild can't recover, so the app tells
            // the user and names the saved file rather than wiping in silence (S10.3 break-it).
            let quarantined = try StoreQuarantine.quarantine(storeURL: url, stamp: stamp)
            return try openPool(url: url, migrator: migrator, quarantinedFrom: quarantined.first)
        } catch let refusal as StoreOpenRefusal {
            throw refusal
        } catch {
            throw StoreOpenRefusal.openFailed(error)
        }
    }

    /// Bring an EXISTING file up to `migrator`'s schema on one plain connection, which writes nothing
    /// until the file is known intact and not from a newer build. Throws a corruption error
    /// for a damaged file and `StoreOpenRefusal` for one that must be left alone. The connection
    /// closes on return, before the pool opens.
    private static func upgradeInPlace(url: URL, migrator: DatabaseMigrator) throws {
        let connection = try DatabaseQueue(path: url.path, configuration: makeConfiguration())
        let upToDate = try connection.read { db in
            guard try String.fetchOne(db, sql: integrityCheckSQL) == "ok" else { throw FailedIntegrityCheck() }
            guard try !migrator.hasBeenSuperseded(db) else { throw StoreOpenRefusal.newerVersion }
            return try migrator.hasCompletedMigrations(db)
        }
        guard !upToDate else { return }
        try migrator.migrate(connection)
    }

    /// Open the store's `DatabasePool` and migrate — the whole schema for a new file, a no-op for an
    /// existing one `upgradeInPlace` already brought current.
    private static func openPool(url: URL, migrator: DatabaseMigrator, quarantinedFrom: URL?) throws -> OpenedStore {
        let pool = try DatabasePool(path: url.path, configuration: makeConfiguration())
        try migrator.migrate(pool)
        return try OpenedStore(writer: pool, version: readSchemaVersion(pool), quarantinedFrom: quarantinedFrom)
    }

    /// Real corruption — the only reason to quarantine: a failed integrity check, or SQLite
    /// reporting a corrupt file / not a database at all.
    private static func isCorruption(_ error: any Error) -> Bool {
        if error is FailedIntegrityCheck {
            return true
        }
        guard let dbError = error as? DatabaseError else { return false }
        let code = dbError.resultCode.primaryResultCode
        return code == .SQLITE_CORRUPT || code == .SQLITE_NOTADB
    }

    /// Read the schema version back from `schema_info` (0 on a fresh, unwritten store).
    private static func readSchemaVersion(_ writer: any DatabaseWriter) throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: selectSchemaVersionSQL) ?? 0 }
    }
}
