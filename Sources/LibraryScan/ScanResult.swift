// ScanResult — the `Sendable` outcome of one root scan (design §2).
//
// Store-agnostic value type produced by `LibraryScanner.scan`. It carries only plain
// scalars + an `[Int64]` id list, so it crosses task/actor boundaries freely (no
// `sqlite3*`, no `SQLiteConnection`).
//
// S8.2b completes it: `orphansSwept` (the end-of-walk `sweepOrphans` count — design
// §9 D-sweep) is now present. It is 0 for a first scan (nothing to reconcile) and, on
// a re-scan, the number of rows deleted because the walk did not re-see them. A
// CANCELLED scan skips the sweep entirely (design §5), so its `orphansSwept` stays 0.

import Foundation

/// The outcome of scanning one registered root into the store.
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
    /// How many orphan rows the end-of-walk sweep removed for THIS root (design §9
    /// D-sweep). 0 on a first scan and on a cancelled scan (the sweep is skipped).
    public let orphansSwept: Int
    /// The stable `tracks.id`s upserted, in walk order.
    public let trackIDs: [Int64]

    public init(
        folderID: Int64, generation: Int64, filesSeen: Int, filesSkipped: Int,
        orphansSwept: Int, trackIDs: [Int64]
    ) {
        self.folderID = folderID
        self.generation = generation
        self.filesSeen = filesSeen
        self.filesSkipped = filesSkipped
        self.orphansSwept = orphansSwept
        self.trackIDs = trackIDs
    }
}
