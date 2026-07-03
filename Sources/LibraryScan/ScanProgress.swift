// ScanProgress — the `Sendable` count-up payload for a scan's progress callback (§5).
//
// S8.2b. The walk is single-pass (`FileManager.enumerator` is lazy; a pre-count
// would double the traversal just to feed a determinate spinner), so progress is an
// INDETERMINATE count-up: `totalFiles` is nil and `filesSeenSoFar` increments per
// batch. Carrying only scalars, it crosses the actor boundary freely — the scanner
// (off-main) fires it, and the VM hops to `@MainActor` to publish it (design §5, §7).
//
// This mirrors the app's existing 20 Hz polled-counter idiom (a bounded-rate value
// snapshot), NOT a first-of-its-kind `AsyncStream`.

import Foundation

/// A snapshot of a scan's progress, fired once per committed batch.
public struct ScanProgress: Sendable, Equatable {
    /// The `folders` rowid of the root being scanned (one root per scan).
    public let folderID: Int64
    /// How many regular, supported-extension files have been seen so far
    /// (monotonically non-decreasing across a single scan's callbacks).
    public let filesSeenSoFar: Int
    /// The total file count if known, or `nil` — the single-pass walk is
    /// INDETERMINATE, so this is always `nil` in S8.2b (design §5). Present so a
    /// future two-pass/determinate mode is a non-breaking fill-in.
    public let totalFiles: Int?

    public init(folderID: Int64, filesSeenSoFar: Int, totalFiles: Int? = nil) {
        self.folderID = folderID
        self.filesSeenSoFar = filesSeenSoFar
        self.totalFiles = totalFiles
    }
}
