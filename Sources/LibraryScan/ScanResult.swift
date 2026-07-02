// ScanResult — the `Sendable` outcome of one root scan (design §2).
//
// S8.2a. Store-agnostic value type produced by `LibraryScanner.scan`. It carries
// only plain scalars + an `[Int64]` id list, so it crosses task/actor boundaries
// freely (no `sqlite3*`, no `SQLiteConnection`). `ScanProgress` (the count-up
// callback payload) is deferred to S8.2b — this chunk is the produce-and-write
// core with no progress plumbing yet.

import Foundation

/// The outcome of scanning one registered root into the store.
///
/// - `orphansSwept` is intentionally ABSENT in S8.2a: the orphan sweep is S8.2b's
///   re-scan reconciliation (design §9 D-sweep). This chunk only inserts/updates.
public struct ScanResult: Sendable, Equatable {
    /// The scanned root's `folders` rowid (as passed in — one root per `scan`).
    public let folderID: Int64
    /// The per-root scan generation stamped onto every touched row (`last_seen_scan`).
    public let generation: Int64
    /// How many regular, supported-extension files were upserted.
    public let filesSeen: Int
    /// How many enumerated entries were skipped (directory / unsupported ext /
    /// unreadable — a failed stat is a skip, not a crash; design §8 TOCTOU).
    public let filesSkipped: Int
    /// The stable `tracks.id`s upserted, in walk order.
    public let trackIDs: [Int64]

    public init(
        folderID: Int64, generation: Int64, filesSeen: Int, filesSkipped: Int,
        trackIDs: [Int64]
    ) {
        self.folderID = folderID
        self.generation = generation
        self.filesSeen = filesSeen
        self.filesSkipped = filesSkipped
        self.trackIDs = trackIDs
    }
}
