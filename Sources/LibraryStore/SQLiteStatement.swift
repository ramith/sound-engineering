// SQLiteStatement — an RAII prepared-statement wrapper.
//
// S8.1a. Wraps a single `sqlite3_stmt*` with bind / step / column accessors and
// guarantees `sqlite3_finalize` on deinit. Bind indices are 1-based (SQLite's
// convention); column indices are 0-based (also SQLite's convention) — kept as
// SQLite has them to avoid a translation layer that could silently drift.
//
// Text/BLOB binds use SQLITE_TRANSIENT so SQLite copies the bytes immediately;
// this frees the caller from having to keep the Swift `String`/`Data` alive until
// step, which is the classic dangling-pointer footgun with SQLITE_STATIC.
//
// Not `Sendable` and never crosses the actor boundary — it holds a raw handle
// owned by one `SQLiteConnection` on one thread.

import Foundation
import SQLite3

/// SQLite's `SQLITE_TRANSIENT` sentinel: instructs SQLite to make its own private
/// copy of bound text/BLOB bytes. The C macro `((sqlite3_destructor_type)-1)` is
/// not imported into Swift, so it is reconstructed here via a bit-cast of -1.
let sqliteTransientDestructor = unsafeBitCast(
    Int(-1), to: sqlite3_destructor_type.self
)

/// A prepared statement bound to one connection. Finalizes on deinit (RAII).
public final class SQLiteStatement {
    private let handle: OpaquePointer
    private let sql: String
    /// True once finalized so a double-finalize (deinit after an explicit close)
    /// is a no-op rather than a use-after-free.
    private var finalized = false

    /// Prepare `sql` on `db`. Throws `SQLiteError.prepareFailed` on failure.
    init(database: OpaquePointer, sql: String) throws {
        self.sql = sql
        var stmt: OpaquePointer?
        let code = sqlite3_prepare_v2(database, sql, -1, &stmt, nil)
        guard code == SQLITE_OK, let prepared = stmt else {
            let message = SQLiteStatement.message(for: database)
            if let stmt { sqlite3_finalize(stmt) }
            throw SQLiteError.prepareFailed(sql: sql, code: code, message: message)
        }
        handle = prepared
    }

    deinit {
        finalize()
    }

    /// Finalize the statement early (idempotent). Deinit also calls this.
    public func finalize() {
        guard !finalized else { return }
        sqlite3_finalize(handle)
        finalized = true
    }

    // MARK: - Binding (1-based indices)

    /// Bind an optional 64-bit integer; `nil` binds SQL NULL.
    public func bind(_ value: Int64?, at index: Int32) throws {
        let code: Int32
        if let value {
            code = sqlite3_bind_int64(handle, index, value)
        } else {
            code = sqlite3_bind_null(handle, index)
        }
        try checkBind(code, index: index)
    }

    /// Bind an optional string; `nil` binds SQL NULL. Uses SQLITE_TRANSIENT so
    /// SQLite copies immediately (no lifetime coupling to the Swift `String`).
    public func bind(_ value: String?, at index: Int32) throws {
        let code: Int32
        if let value {
            code = sqlite3_bind_text(handle, index, value, -1, sqliteTransientDestructor)
        } else {
            code = sqlite3_bind_null(handle, index)
        }
        try checkBind(code, index: index)
    }

    /// Bind an optional BLOB; `nil` (or empty) binds SQL NULL. Uses
    /// SQLITE_TRANSIENT so SQLite copies immediately.
    public func bind(_ value: Data?, at index: Int32) throws {
        guard let value, !value.isEmpty else {
            try checkBind(sqlite3_bind_null(handle, index), index: index)
            return
        }
        let code = value.withUnsafeBytes { raw -> Int32 in
            sqlite3_bind_blob(handle, index, raw.baseAddress, Int32(raw.count), sqliteTransientDestructor)
        }
        try checkBind(code, index: index)
    }

    // MARK: - Stepping

    /// Advance one row. Returns `true` for `SQLITE_ROW`, `false` for
    /// `SQLITE_DONE`. Maps constraint failures to `.constraintViolation` and any
    /// other non-row/done code to `.stepFailed`.
    public func step() throws -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        case SQLITE_CONSTRAINT:
            throw SQLiteError.constraintViolation(code: code, message: currentDatabaseMessage())
        default:
            throw SQLiteError.stepFailed(code: code, message: currentDatabaseMessage())
        }
    }

    /// Reset the statement so it can be re-stepped (bindings are retained).
    public func reset() {
        sqlite3_reset(handle)
    }

    /// Clear all bindings back to NULL.
    public func clearBindings() {
        sqlite3_clear_bindings(handle)
    }

    // MARK: - Column accessors (0-based indices)

    /// Read column `index` as `Int64` (0 for a NULL/absent column).
    public func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    /// Read column `index` as `Int`.
    public func columnInt(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(handle, index))
    }

    /// Read column `index` as `String`, or `nil` if the column is SQL NULL.
    public func columnText(_ index: Int32) -> String? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(handle, index)
        else {
            return nil
        }
        return String(cString: cString)
    }

    /// True if column `index` is SQL NULL in the current row.
    public func columnIsNull(_ index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    // MARK: - Private

    private func checkBind(_ code: Int32, index: Int32) throws {
        guard code == SQLITE_OK else {
            throw SQLiteError.bindFailed(index: index, code: code, message: currentDatabaseMessage())
        }
    }

    /// The `sqlite3_errmsg` of this statement's owning connection.
    private func currentDatabaseMessage() -> String {
        guard let database = sqlite3_db_handle(handle) else {
            return "no database handle for statement (\(sql))"
        }
        return SQLiteStatement.message(for: database)
    }

    /// Decode `sqlite3_errmsg` for `db` into a Swift string.
    public static func message(for database: OpaquePointer) -> String {
        guard let cString = sqlite3_errmsg(database) else { return "unknown error" }
        return String(cString: cString)
    }
}
