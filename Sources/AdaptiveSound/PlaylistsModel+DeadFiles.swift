import Foundation
import LibraryStore

// MARK: - PlaylistsModel + dead/missing-file resolution (F)

/// Missing-file resolution helpers, split from `PlaylistsModel` for type-body length. The mutating
/// verbs (`confirmRemoveMissing` / `relocateEntry`) stay in the main file (they move the dialog
/// latch, which is file-private); these are stateless / read-only.
extension PlaylistsModel {
    /// Off-main file-existence resolution (F): entry ids whose track resolved AND whose file exists.
    /// `PlaylistEntry` / `LibraryTrackDisplay` are `Sendable`, so the `fileExists` stat loop runs
    /// detached at `.utility` off the main actor (a large playlist mustn't jank the open).
    static func availableEntryIDs(entries: [PlaylistEntry],
                                  displays: [Int64: LibraryTrackDisplay]) async -> Set<Int64> {
        await Task.detached(priority: .utility) {
            var available = Set<Int64>()
            for entry in entries {
                if let url = displays[entry.trackID]?.url, FileManager.default.fileExists(atPath: url.path) {
                    available.insert(entry.id)
                }
            }
            return available
        }.value
    }

    /// Count of unavailable (missing-file) entries in the open detail — drives the "Remove missing"
    /// affordance + the count-line suffix.
    var missingEntryCount: Int {
        detail.count { !$0.isAvailable }
    }

    /// The unavailable (missing-file) entries of the open detail, in order: what Remove Missing asks
    /// about, and what an open confirmation is re-checked against.
    var missingEntryIDs: [Int64] {
        detail.filter { !$0.isAvailable }.map(\.id)
    }

    /// Whether a scan / metadata pass / reconcile is populating the library — availability is a live
    /// `fileExists` snapshot that flickers "missing" mid-scan, so bulk "Remove missing" is gated off it.
    var isLibraryPopulating: Bool {
        library.scanProgress != nil || library.metadataProgress != nil || library.isReconciling
    }
}
