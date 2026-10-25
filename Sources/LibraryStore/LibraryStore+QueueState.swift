// LibraryStore+QueueState — the queue's resume state (v10; R1.1-B, council C-65): read whole, written
// whole, each in ONE transaction, so a crash or a force-quit at any instant leaves the previous state or
// the next one — never a record from one write with a playhead from another.
//
// The store keeps what the app's one writer hands it (AudioViewModel+QueueMirror) and returns it as it was:
// the record's text — PlaybackQueueKit's `QueueResumeRecord`, which the store does not read — and the
// offset beside it. Each new record takes the next revision; a playhead write names the revision it
// belongs to and is refused, writing nothing, when the stored record is another one.

import Foundation
import GRDB

/// The queue's resume state as stored: the record's text, its revision, and the playhead that belongs to
/// it.
public struct StoredQueueState: Sendable, Equatable {
    /// Grows by one with each record written.
    public let revision: Int64
    /// The record, as the writer encoded it.
    public let record: String
    /// Seconds into the selected song; nil when no playhead belongs to this revision.
    public let offset: Double?

    public init(revision: Int64, record: String, offset: Double?) {
        self.revision = revision
        self.record = record
        self.offset = offset
    }
}

public extension LibraryStore {
    // MARK: - SQL

    /// The record and the playhead of the same revision, in one statement (one snapshot).
    private static let selectQueueStateSQL = """
    SELECT s.revision, s.record, p.offset_seconds
    FROM queue_state s LEFT JOIN queue_playhead p ON p.id = 1 AND p.revision = s.revision
    WHERE s.id = 1;
    """
    /// A new record: revision 1, or the stored one's + 1.
    private static let upsertQueueStateSQL = """
    INSERT INTO queue_state(id, revision, record, written_at) VALUES (1, 1, ?, ?)
    ON CONFLICT(id) DO UPDATE SET revision = revision + 1, record = excluded.record, written_at = excluded.written_at
    RETURNING revision;
    """
    private static let upsertQueuePlayheadSQL = """
    INSERT INTO queue_playhead(id, revision, offset_seconds, written_at) VALUES (1, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET revision = excluded.revision, offset_seconds = excluded.offset_seconds,
        written_at = excluded.written_at;
    """
    /// Move the playhead of revision `?` — only while that revision is the stored record's.
    private static let updateQueuePlayheadSQL = """
    UPDATE queue_playhead SET offset_seconds = ?, written_at = ?
    WHERE id = 1 AND revision = ? AND revision = (SELECT revision FROM queue_state WHERE id = 1);
    """

    // MARK: - Reads

    /// The stored queue state, or nil when no record was ever written (a new library, or one a build
    /// before v10 kept: its queue is still in the "current" playlist).
    func queueState() async throws -> StoredQueueState? {
        try await dbWriter.read { db in
            try Row.fetchOne(db, sql: Self.selectQueueStateSQL).map { row in
                StoredQueueState(revision: row[0], record: row[1], offset: row[2])
            }
        }
    }

    // MARK: - Writes (the app's one queue writer only)

    /// Replace the record with `record` and its playhead with `offset`, in ONE transaction. Returns the new
    /// revision. A failure writes nothing: the previous record and its playhead stay as they were.
    @discardableResult
    func saveQueueState(record: String, offset: Double) async throws -> Int64 {
        try await dbWriter.write { db in
            let now = LibraryStore.nowSeconds()
            guard let revision = try Int64.fetchOne(db, sql: Self.upsertQueueStateSQL, arguments: [record, now]) else {
                throw SQLiteError.internalError(message: "queue_state upsert returned no revision")
            }
            try db.execute(sql: Self.upsertQueuePlayheadSQL, arguments: [revision, offset, now])
            return revision
        }
    }

    /// Move the playhead of the record `revision` to `offset`, in ONE transaction. Returns false — having
    /// written nothing — when the stored record is another revision: the caller writes the whole state.
    func saveQueuePlayhead(_ offset: Double, revision: Int64) async throws -> Bool {
        try await dbWriter.write { db in
            try db.execute(sql: Self.updateQueuePlayheadSQL,
                           arguments: [offset, LibraryStore.nowSeconds(), revision])
            return db.changesCount == 1
        }
    }
}
