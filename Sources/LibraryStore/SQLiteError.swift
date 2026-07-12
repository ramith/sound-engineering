// SQLiteError — the LibraryStore DAO's typed domain errors.
//
// The store is built on GRDB, which surfaces its own `DatabaseError` for SQLite-level
// failures (constraint / corruption / busy / …). `LibraryStore` maps the conditions it acts
// on into domain types — a `UNIQUE(url)` collision becomes `URLConflict` (LibraryTypes);
// corruption or a too-new schema are detected from a `DatabaseError` inside the store's open
// path and drive quarantine + rebuild there. Only these two app-level conditions remain as a
// typed `SQLiteError`. No `Database`/`sqlite3*` handle ever escapes into an error value.

import Foundation

/// A typed domain error surfaced by the library store.
public enum SQLiteError: Error, Sendable {
    /// A DAO invariant failed (an unexpected NULL, or a row just written that is then not
    /// found by its unique key — a "should never happen" the DAO surfaces rather than masks).
    case internalError(message: String)
    /// This SQLite build lacks the FTS5 extension, which schema v2 requires (S9.2).
    /// Deliberately NOT rebuild-recoverable: a valid store must fail to open (surface the
    /// reason), never be quarantined for a missing extension.
    case fts5Unavailable

    /// Whether a quarantine + rebuild recovers from this error — always `false`:
    /// `fts5Unavailable` is a build/config fault a valid store must surface (not paper over),
    /// and `internalError` is a logic invariant, not corruption. (Corruption / a too-new
    /// schema are recognised from GRDB's `DatabaseError` inside the store's open path, not here.)
    public var isRebuildRecoverable: Bool {
        false
    }
}

extension SQLiteError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .internalError(message):
            return "LibraryStore internal error: \(message)"
        case .fts5Unavailable:
            return "SQLite FTS5 extension unavailable; full-text search (schema v2) cannot be created"
        }
    }
}
