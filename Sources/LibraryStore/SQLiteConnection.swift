// SQLiteConnection — a thin RAII wrapper over one `sqlite3*` connection.
//
// S8.1a. Owns exactly one open connection: opens with WAL + foreign_keys + a
// busy_timeout (design §5), exposes exec / prepare / transaction / user_version /
// integrity_check / last_insert_rowid, and closes on deinit (RAII). It is NOT
// `Sendable` and must be used from a single isolation domain — the `LibraryStore`
// actor. No `sqlite3*` handle is ever exposed publicly.

import Foundation
import SQLite3

/// A single SQLite database connection with the store's pragmas applied at open.
public final class SQLiteConnection {
    private let handle: OpaquePointer
    private var closed = false

    /// Open (creating if absent) the database at `path` and apply the store
    /// pragmas: WAL journal mode, `foreign_keys=ON`, `synchronous=NORMAL`, and a
    /// `busy_timeout`. Throws `SQLiteError.openFailed` if the file cannot be
    /// opened. Opening a *corrupt* file typically succeeds here (SQLite defers
    /// the header check) — corruption is caught by `integrityCheck()` afterwards.
    ///
    /// - Parameters:
    ///   - path: filesystem path (":memory:" for an in-memory database).
    ///   - busyTimeoutMillis: `busy_timeout` in milliseconds (default 5000).
    public init(path: String, busyTimeoutMillis: Int32 = 5000) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let code = sqlite3_open_v2(path, &database, flags, nil)
        guard code == SQLITE_OK, let opened = database else {
            let message: String
            if let database {
                message = SQLiteStatement.message(for: database)
                sqlite3_close(database)
            } else if let errStr = sqlite3_errstr(code) {
                message = String(cString: errStr)
            } else {
                message = "unknown open error"
            }
            throw SQLiteError.openFailed(code: code, message: message)
        }
        handle = opened

        // busy_timeout FIRST so the subsequent pragmas honour it under contention.
        sqlite3_busy_timeout(handle, busyTimeoutMillis)
        do {
            try exec("PRAGMA journal_mode=WAL;")
            try exec("PRAGMA foreign_keys=ON;")
            try exec("PRAGMA synchronous=NORMAL;")
        } catch {
            sqlite3_close(handle)
            closed = true
            throw error
        }
    }

    deinit {
        close()
    }

    /// Close the connection early (idempotent). Deinit also calls this. Uses
    /// `sqlite3_close_v2` so any statements the caller failed to finalize are
    /// cleaned up as they release rather than leaking the handle.
    public func close() {
        guard !closed else { return }
        sqlite3_close_v2(handle)
        closed = true
    }

    // MARK: - Exec / prepare

    /// Execute one or more semicolon-separated statements with no result rows.
    public func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard code == SQLITE_OK else {
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
                sqlite3_free(errorPointer)
            } else {
                message = SQLiteStatement.message(for: handle)
            }
            if code == SQLITE_CONSTRAINT {
                throw SQLiteError.constraintViolation(code: code, message: message)
            }
            throw SQLiteError.execFailed(sql: sql, code: code, message: message)
        }
    }

    /// Prepare `sql` into an RAII `SQLiteStatement` bound to this connection.
    public func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(database: handle, sql: sql)
    }

    /// Rowid of the most recent successful INSERT on this connection.
    public func lastInsertRowID() -> Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    /// Number of rows changed by the most recent INSERT/UPDATE/DELETE.
    public func changes() -> Int {
        Int(sqlite3_changes(handle))
    }

    // MARK: - Convenience query helpers

    /// Execute a parameterless statement expected to yield a single integer in
    /// column 0 (e.g. `SELECT count(*)`). Returns `nil` if no row is produced.
    public func scalarInt(_ sql: String) throws -> Int64? {
        let statement = try prepare(sql)
        defer { statement.finalize() }
        return try statement.step() ? statement.columnInt64(0) : nil
    }

    /// Execute a parameterless statement expected to yield a single text value in
    /// column 0. Returns `nil` if no row is produced or the value is NULL.
    public func scalarText(_ sql: String) throws -> String? {
        let statement = try prepare(sql)
        defer { statement.finalize() }
        return try statement.step() ? statement.columnText(0) : nil
    }

    // MARK: - Transactions

    /// Run `body` inside a `BEGIN IMMEDIATE … COMMIT`. On any thrown error the
    /// transaction is rolled back and the error re-thrown. `BEGIN IMMEDIATE`
    /// acquires the write lock up front (design §5, single-writer discipline) so
    /// a writer never fails a later step with `SQLITE_BUSY` mid-transaction.
    @discardableResult
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            // Best-effort rollback; preserve and re-throw the original error. If
            // ROLLBACK itself fails there is nothing more the caller can do, and
            // masking the original error would hide the real cause.
            try? exec("ROLLBACK;")
            throw error
        }
    }

    // MARK: - user_version

    /// Read `PRAGMA user_version` (0 on a fresh database).
    public func userVersion() throws -> Int {
        try Int(scalarInt("PRAGMA user_version;") ?? 0)
    }

    /// Set `PRAGMA user_version`. Note: `user_version` cannot be parameter-bound,
    /// so the integer is interpolated — safe because it is a validated `Int`.
    public func setUserVersion(_ version: Int) throws {
        try exec("PRAGMA user_version = \(version);")
    }

    // MARK: - Integrity

    /// Run `PRAGMA integrity_check` and return `true` iff SQLite reports "ok".
    /// A corrupt database yields one or more problem rows; the first is surfaced
    /// via a thrown `SQLiteError.integrityCheckFailed` from `integrityCheckStrict`.
    public func integrityCheck() throws -> Bool {
        let result = try scalarText("PRAGMA integrity_check(1);")
        return result == "ok"
    }

    /// Like `integrityCheck()` but throws `.integrityCheckFailed` (with the first
    /// problem row) when the check does not return "ok".
    public func integrityCheckStrict() throws {
        let result = try scalarText("PRAGMA integrity_check(1);")
        guard result == "ok" else {
            throw SQLiteError.integrityCheckFailed(details: result ?? "no result row")
        }
    }

    /// The current `journal_mode` (e.g. "wal") — used by the harness to assert WAL.
    public func journalMode() throws -> String {
        try scalarText("PRAGMA journal_mode;") ?? "unknown"
    }

    /// The current `foreign_keys` pragma (1 when enforcement is ON).
    public func foreignKeysEnabled() throws -> Bool {
        try (scalarInt("PRAGMA foreign_keys;") ?? 0) == 1
    }

    /// The current `busy_timeout` in milliseconds.
    public func busyTimeout() throws -> Int {
        try Int(scalarInt("PRAGMA busy_timeout;") ?? 0)
    }
}
