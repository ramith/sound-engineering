import Foundation
import LibraryScan
import LibraryStore

// MARK: - LibraryModel "Use this drive" (R1.1-B, US-R1F-03 LIB-VOL-1; seam S4)

//
// A paused music folder pointed at the folder that holds its songs on another drive: the rebind looks for
// each song there by its path under the folder (+ its size) and re-roots the folder in one store
// transaction — the songs found keep their ids and history, the rest are removed with theirs, and nothing
// changes when none is found (`RootRebinder`, `LibraryStore.rebindRoot`; the founder's rule, 2026-10-25).
// After a rebind the folder is no longer paused: the watcher follows its new path, and a reconcile walk —
// an ordinary one, on the folder's confirmed drive — picks up any song new on the drive.

extension LibraryModel {
    /// Rebind folder `folderID` to `newRoot` (see the extension's header). Returns what happened, or nil
    /// when the library has no store or the rebind failed (said through `onError`).
    func useDrive(_ newRoot: URL, forFolder folderID: Int64) async -> RebindOutcome? {
        guard let store else { return nil }
        let didAccess = newRoot.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                newRoot.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                try await RootRebinder().rebind(folderID: folderID, to: newRoot, in: store)
            }.value
            logUX("useDrive: folder \(folderID) → '\(Self.makeDisplayPath(newRoot))' — \(outcome)")
            if case .rebound = outcome {
                reconcileState[folderID] = nil
                await refreshWatchedRoots()
                requestWalk(.reconcile, of: folderID)
                libraryRevision &+= 1 // songs left, urls moved: the browse lists and playlists reload
            }
            return outcome
        } catch {
            logUX("useDrive: folder \(folderID) failed — \(error)")
            onError?("Couldn’t use that drive: \(error.localizedDescription)")
            return nil
        }
    }
}
