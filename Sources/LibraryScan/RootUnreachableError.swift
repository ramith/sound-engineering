// RootUnreachableError — the empty-walk safety guard's typed throw (S8.4 slice 3).
//
// `LibraryScanner.scan` throws this when a root's walk enumerated ZERO files while the store
// still holds rows for that root. An unmounted/zombie-mounted volume or a deleted root folder
// is indistinguishable from "every file deleted" via an empty walk, so the scanner REFUSES
// the mass sweep and throws instead — the rows (and their durable user-state: play-count,
// loved, rating, future playlist memberships) are preserved. The VM catches it silently, the
// way it already catches `CancellationError` (a background non-event); a later reconcile of a
// reachable root reaps genuine deletions, which are positively evidenced by a non-empty walk.

import Foundation

/// Thrown by `LibraryScanner.scan` when the empty-walk safety guard refuses a mass sweep.
public struct RootUnreachableError: Error, Sendable, Equatable {
    /// The `folders` rowid whose walk came back empty while rows still existed.
    public let folderID: Int64
    /// How many rows the store held for that root when the sweep was refused.
    public let storedRowCount: Int

    public init(folderID: Int64, storedRowCount: Int) {
        self.folderID = folderID
        self.storedRowCount = storedRowCount
    }
}
