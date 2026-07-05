// SQLiteError — typed errors for the thin SQLite wrapper.
//
// S8.1a (persistent library-store foundation). Every failable SQLite call in
// `SQLiteConnection` / `SQLiteStatement` funnels through these cases so callers
// (the `LibraryStore` actor, the migration runner, the verify harness) get a
// `Swift.Error` with the SQLite result code, the human-readable message, and —
// where relevant — the SQL that failed. No `sqlite3*` handle ever escapes into
// an error value, keeping everything `Sendable`.

import Foundation
import SQLite3

/// A typed error surfaced by the SQLite wrapper. Carries the raw SQLite result
/// code plus a decoded message so failures are diagnosable without a live handle.
public enum SQLiteError: Error, Sendable {
    /// `sqlite3_open_v2` failed. `code` is the SQLite result code; `message` is
    /// the decoded `sqlite3_errmsg` (or the errstr fallback when no handle exists).
    case openFailed(code: Int32, message: String)
    /// `sqlite3_exec` failed for `sql`. `code`/`message` decode the failure.
    case execFailed(sql: String, code: Int32, message: String)
    /// `sqlite3_prepare_v2` failed for `sql`.
    case prepareFailed(sql: String, code: Int32, message: String)
    /// A bind call (`sqlite3_bind_*`) failed for the 1-based `index`.
    case bindFailed(index: Int32, code: Int32, message: String)
    /// `sqlite3_step` returned neither `SQLITE_ROW` nor `SQLITE_DONE`.
    case stepFailed(code: Int32, message: String)
    /// A `UNIQUE`/primary-key constraint was violated. Kept distinct from
    /// `stepFailed` so the DAO (S8.1b) can surface the typed `UNIQUE(url)`
    /// conflict `moveTrack`/`upsert` care about (design §4, M6).
    case constraintViolation(code: Int32, message: String)
    /// `PRAGMA integrity_check` returned a non-`ok` result. `details` is the
    /// first problem row SQLite reported.
    case integrityCheckFailed(details: String)
    /// The on-disk `user_version` is newer than the app's schema (downgrade
    /// guard — design §5). The store must quarantine + rebuild rather than run
    /// an unknown-newer schema.
    case schemaTooNew(found: Int, supported: Int)
    /// A migration step for `version` is not registered in the runner.
    case migrationMissing(version: Int)
    /// This SQLite build lacks the FTS5 extension, which schema v2 requires
    /// (S9.2). Deliberately NOT rebuild-recoverable: a valid store must fail to
    /// open (surface the reason), never be quarantined for a missing extension.
    case fts5Unavailable
    /// A generic wrapper failure (unexpected NULL handle, encoding failure, …).
    case internalError(message: String)

    /// The underlying SQLite result code where one applies (for `SQLITE_BUSY`
    /// discrimination in tests / callers), else `nil`.
    public var sqliteCode: Int32? {
        switch self {
        case let .openFailed(code, _),
             let .execFailed(_, code, _),
             let .prepareFailed(_, code, _),
             let .bindFailed(_, code, _),
             let .stepFailed(code, _),
             let .constraintViolation(code, _):
            return code
        case .integrityCheckFailed, .schemaTooNew, .migrationMissing, .fts5Unavailable, .internalError:
            return nil
        }
    }

    /// True when this is a `UNIQUE`/PK constraint violation — the DAO maps it to a
    /// typed `URLConflict` for `moveTrack`/`upsert` (design §4, M6). Covers both the
    /// dedicated `.constraintViolation` case and a raw `SQLITE_CONSTRAINT` surfaced
    /// as a `.stepFailed`.
    public var isConstraintViolation: Bool {
        if case .constraintViolation = self { return true }
        return sqliteCode == SQLITE_CONSTRAINT
    }

    /// True when the underlying SQLite result code is `SQLITE_BUSY` — a writer held
    /// the lock past the `busy_timeout`. The concurrency harness discriminates on it.
    public var isBusy: Bool {
        sqliteCode == SQLITE_BUSY
    }

    /// True when the underlying SQLite result code means "this file is not a
    /// usable database": SQLITE_CORRUPT (11) or SQLITE_NOTADB (26). Used by
    /// `LibraryStore` to decide when to quarantine + rebuild.
    public var indicatesCorruption: Bool {
        guard let code = sqliteCode else { return false }
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
    }

    /// True for errors a quarantine + rebuild recovers from: an underlying
    /// corruption code, a failed integrity check, or the downgrade guard.
    public var isRebuildRecoverable: Bool {
        switch self {
        case .integrityCheckFailed, .schemaTooNew:
            return true
        default:
            return indicatesCorruption
        }
    }
}

extension SQLiteError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .openFailed(code, message):
            return "SQLite open failed (code \(code)): \(message)"
        case let .execFailed(sql, code, message):
            return "SQLite exec failed (code \(code)): \(message) — SQL: \(sql)"
        case let .prepareFailed(sql, code, message):
            return "SQLite prepare failed (code \(code)): \(message) — SQL: \(sql)"
        case let .bindFailed(index, code, message):
            return "SQLite bind failed at index \(index) (code \(code)): \(message)"
        case let .stepFailed(code, message):
            return "SQLite step failed (code \(code)): \(message)"
        case let .constraintViolation(code, message):
            return "SQLite constraint violation (code \(code)): \(message)"
        case let .integrityCheckFailed(details):
            return "SQLite integrity_check failed: \(details)"
        case let .schemaTooNew(found, supported):
            return "Store schema version \(found) is newer than supported \(supported)"
        case let .migrationMissing(version):
            return "No migration step registered for schema version \(version)"
        case .fts5Unavailable:
            return "SQLite FTS5 extension unavailable; full-text search (schema v2) cannot be created"
        case let .internalError(message):
            return "SQLite wrapper internal error: \(message)"
        }
    }
}
