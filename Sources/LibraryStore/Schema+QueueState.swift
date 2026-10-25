// Schema+QueueState — the v9 → v10 migration (R1.1-B; council C-65, KI-PB-21): the queue's resume state.
//
// The queue's songs lived in the built-in "current" playlist and its cursor in the defaults: two stores,
// written at different times, so a crash or a force-quit could leave a queue from one moment and a cursor
// from another, or lose the place altogether, and a loose file — no `tracks` row — could not be kept at
// all. Its state now lives in two one-row tables the app's one writer replaces in ONE transaction:
//   • `queue_state` — the resume record as PlaybackQueueKit encodes it (`QueueResumeRecord`, JSON: the
//     slots by `QueueSlotRef` — a library song by id, a loose file by path, no row needed — the selected
//     slot and the shuffle pass), with a `revision` that grows by one with each new record;
//   • `queue_playhead` — the offset into the selected song, and the revision of the record it belongs to.
//     A playing song's place moves every few seconds; it is rewritten alone, as a number, never the queue.
// The store keeps the record's text as given and reads it back whole; what it means is the Kit's.
//
// ADDITIVE and data-preserving: two new tables, nothing else touched. The "current" playlist and its
// entries stay as they are — the app reads them once, when no record exists yet, to carry an upgrading
// user's queue over — and no foreign key is involved (a loose slot names a path, and a stored track id
// that is gone is dropped when the record is resolved, as the playlist's cascade used to drop it).

import Foundation
import GRDB

public extension Schema.MigrationID {
    /// v9 → v10: the queue's resume state, one record written in one transaction (R1.1-B, C-65). Declared
    /// here, beside its migration: `Schema`'s own body is at its length limit.
    static let v10 = "v10-queue-state"
}

public extension Schema {
    /// The v10 tables. One row each (`id = 1`), so "the" queue state is a primary-key read. The checks
    /// make a half-formed row impossible to store: a record revision is positive, a playhead is a place.
    static let createV10Statements: [String] = [
        """
        CREATE TABLE queue_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            revision INTEGER NOT NULL CHECK (revision >= 1),
            record TEXT NOT NULL,
            written_at INTEGER NOT NULL);
        """,
        """
        CREATE TABLE queue_playhead (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            revision INTEGER NOT NULL,
            offset_seconds REAL NOT NULL CHECK (offset_seconds >= 0),
            written_at INTEGER NOT NULL);
        """,
    ]

    /// Migrate v9 → v10: add the queue-state tables. Additive; every existing row keeps its data.
    static func migrateV9toV10(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV10Statements {
            try db.execute(sql: statement)
        }
        try writeSchemaInfo(db, version: 10, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
