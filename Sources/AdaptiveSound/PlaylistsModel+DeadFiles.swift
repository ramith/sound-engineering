import Foundation
import LibraryScan
import LibraryStore

// MARK: - PlaylistsModel + dead/missing-file resolution (F)

/// Missing-file resolution helpers, split from `PlaylistsModel` for type-body length. The mutating
/// verbs (`confirmRemoveMissing` / `relocateEntry`) stay in the main file (they move the dialog
/// latch, which is file-private); these are stateless / read-only.
extension PlaylistsModel {
    /// Off-main availability resolution (F; R1.1-A KI-LIB-01): each entry's `FileAvailability` — its
    /// file there, or MISSING only when its music folder is there on its own drive (the library's own
    /// sweep evidence, `LibraryScanner.availability`), else UNREACHABLE. An entry whose track did not
    /// resolve has no file to look at: missing. `PlaylistEntry` / `LibraryTrackDisplay` are `Sendable`,
    /// so the disk looks run detached at `.utility` off the main actor (a large playlist mustn't jank
    /// the open).
    static func entryAvailability(entries: [PlaylistEntry], displays: [Int64: LibraryTrackDisplay],
                                  store: LibraryStore) async throws -> [Int64: FileAvailability] {
        try await Task.detached(priority: .utility) {
            let urls = entries.compactMap { displays[$0.trackID]?.url }
            let byURL = try await LibraryScanner().availability(of: urls, in: store)
            var availability: [Int64: FileAvailability] = [:]
            for entry in entries {
                availability[entry.id] = displays[entry.trackID].flatMap { byURL[$0.url] } ?? .missing
            }
            return availability
        }.value
    }

    /// Count of unavailable entries in the open detail (missing or unreachable) — the count line's
    /// "· N unavailable".
    var unavailableEntryCount: Int {
        detail.count { !$0.isAvailable }
    }

    /// Count of missing entries in the open detail — drives the "Remove N Missing…" affordance.
    var missingEntryCount: Int {
        detail.count { $0.availability == .missing }
    }

    /// Count of unreachable entries in the open detail — the ones Remove Missing keeps, and says so.
    var unreachableEntryCount: Int {
        detail.count { $0.availability == .unreachable }
    }

    /// The missing entries of the open detail, in order: what Remove Missing asks about, and what an
    /// open confirmation is re-checked against. Never an unreachable one (KI-LIB-01).
    var missingEntryIDs: [Int64] {
        detail.filter { $0.availability == .missing }.map(\.id)
    }

    /// Whether a scan / metadata pass / reconcile is populating the library — availability is a live
    /// look at the disk that flickers "missing" mid-scan, so bulk "Remove missing" is gated off it.
    var isLibraryPopulating: Bool {
        library.scanProgress != nil || library.metadataProgress != nil || library.isReconciling
    }
}
