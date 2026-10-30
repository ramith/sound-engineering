import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import TrackLoudnessKit

// MARK: - LibraryModel "Use this drive" (R1.1-B, US-R1F-03 LIB-VOL-1; seam S4)

//
// A paused music folder pointed at the folder that holds its songs on another drive: the rebind looks for
// each song there by its path under the folder (+ its size) and re-roots the folder in one store
// transaction — the songs found keep their ids and history, the rest are removed with theirs, and nothing
// changes when none is found (`RootRebinder`, `LibraryStore.rebindRoot`; the founder's rule, 2026-10-25).
// After a rebind the folder is no longer paused: the watcher follows its new path, and a reconcile walk —
// an ordinary one, on the folder's confirmed drive — picks up any song new on the drive.
//
// One choice serves the whole drive (plan check §6, "Use this drive" (10)): the other paused music folders
// bound to the same old drive move along with the one chosen — each looked for at its own place on the drive
// as mounted now (`RootRebinder.location`), by the same rule, silently. One that is not there, or holds none
// of its songs, stays paused, to be pointed elsewhere by hand.
//
// While a drive is checked — seconds, for a large folder on a USB disk — every folder it serves says
// "Checking the drive…" and offers nothing else (`checkingDriveFolderIDs`), so a second choice cannot start
// a second rebind. The disk and store work runs off the main actor, cancellable with its caller.

extension LibraryModel {
    /// What "Use This Drive…" did: the chosen folder's outcome, and the folders of its drive that moved
    /// along with it.
    struct DriveRebind: Sendable {
        let outcome: RebindOutcome
        let movedAlong: [MusicFolderStatus.MovedAlong]
    }

    /// Rebind folder `folderID` to `newRoot`, and the paused folders of its drive along with it (see the
    /// extension's header). Returns what happened, or nil when the library has no store, the folder is being
    /// checked already, or the rebind failed (said through `onError`).
    func useDrive(_ newRoot: URL, forFolder folderID: Int64) async -> DriveRebind? {
        guard let store, !checkingDriveFolderIDs.contains(folderID) else { return nil }
        checkingDriveFolderIDs.insert(folderID)
        let along = await foldersOfItsDrive(folderID, in: store)
        let checking = Set(along.others.map(\.id)).subtracting(checkingDriveFolderIDs)
        checkingDriveFolderIDs.formUnion(checking)
        defer { checkingDriveFolderIDs.subtract(checking.union([folderID])) }
        let didAccess = newRoot.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                newRoot.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let result = try await Self.rebind(folderID, to: newRoot, oldPath: along.oldPath,
                                               along: along.others.filter { checking.contains($0.id) }, in: store)
            logUX("useDrive: folder \(folderID) → '\(Self.makeDisplayPath(newRoot))' — \(result.outcome); "
                + "\(result.movedAlong.count) more moved along")
            if case .rebound = result.outcome {
                for id in [folderID] + result.movedAlong.map(\.id) {
                    reconcileState[id] = nil
                    requestWalk(.reconcile, of: id)
                }
                await refreshWatchedRoots()
                libraryRevision &+= 1 // songs left, urls moved: the browse lists and playlists reload
                await rekeyAnalyses(Self.folderMoves(along: along, rebound: result.movedAlong, to: newRoot))
            }
            return DriveRebind(outcome: result.outcome, movedAlong: result.movedAlong.map(\.said))
        } catch {
            logUX("useDrive: folder \(folderID) failed — \(error)")
            onError?("Couldn’t use that drive: \(error.localizedDescription)")
            return nil
        }
    }

    /// The songs' analyses follow them (R1.1-B, US-R1F-10 item 16; level-and-fold "The store and the scheduler"):
    /// the analysis store the library was handed is re-keyed for each folder move, `(from, to)`, so the drive's songs
    /// are not measured again. A move that fails leaves its records where they were (its songs are measured again,
    /// as new files), logged.
    private func rekeyAnalyses(_ moves: [(from: String, to: String)]) async {
        guard let analysisStore else { return }
        for move in moves {
            do {
                let moved = try await analysisStore.rekey(root: move.from, to: move.to)
                logUX("useDrive: \(moved) song analyses moved to '\(move.to)'")
            } catch {
                logUX("useDrive: the song analyses under '\(move.from)' could not be moved — \(error)")
            }
        }
    }

    /// Folder `folderID`'s path, and the other music folders bound to its drive that are paused and offered
    /// "Use This Drive…" — the ones that can move along with it. None when the folder is bound to no drive.
    private func foldersOfItsDrive(_ folderID: Int64, in store: LibraryStore) async
        -> (oldPath: String?, others: [LibraryFolder]) {
        guard let volume = try? await store.boundVolume(ofRoot: folderID),
              let folders = try? await store.roots(onVolume: volume) else { return (nil, []) }
        let others = folders.filter { folder in
            folder.id != folderID
                && MusicFolderStatus(isScanning: false, pausedBy: reconcileState[folder.id]?.pauseReason)?
                .offersUseThisDrive == true
        }
        return (folders.first { $0.id == folderID }?.path, others)
    }

    /// Each music folder a rebind moved, from its old path to its new one: the one chosen (`along.oldPath` to
    /// `newRoot`) and those of `rebound` that moved along, each at its own place on the drive as mounted now.
    private static func folderMoves(along: (oldPath: String?, others: [LibraryFolder]), rebound: [MovedFolder],
                                    to newRoot: URL) -> [(from: String, to: String)] {
        guard let oldPath = along.oldPath else { return [] }
        let newPath = PathNormalizer.normalizedString(for: newRoot)
        let moved = Set(rebound.map(\.id))
        return [(oldPath, newPath)] + along.others.filter { moved.contains($0.id) }.compactMap { folder in
            RootRebinder.location(of: folder.path, movedFrom: oldPath, to: newPath).map { (folder.path, $0) }
        }
    }

    /// A folder that moved along with the one chosen: its id, and what the app says of it.
    private struct MovedFolder: Sendable {
        let id: Int64
        let said: MusicFolderStatus.MovedAlong
    }

    /// The rebind itself, off the main actor: `folderID` to `newRoot`; then — when it was rebound from
    /// `oldPath` — each of `along` at its own place on the drive as mounted now, where there is a folder
    /// there. A folder of `along` refused, or failing, stays as it was.
    @concurrent
    private nonisolated static func rebind(
        _ folderID: Int64, to newRoot: URL, oldPath: String?, along: [LibraryFolder], in store: LibraryStore
    ) async throws -> (outcome: RebindOutcome, movedAlong: [MovedFolder]) {
        let outcome = try await RootRebinder().rebind(folderID: folderID, to: newRoot, in: store)
        guard case .rebound = outcome, let oldPath else { return (outcome, []) }
        let newPath = PathNormalizer.normalizedString(for: newRoot)
        var moved: [MovedFolder] = []
        for folder in along {
            try Task.checkCancellation()
            guard let place = RootRebinder.location(of: folder.path, movedFrom: oldPath, to: newPath) else { continue }
            let target = URL(fileURLWithPath: place, isDirectory: true)
            guard RootReachabilityProbe.isReachable(target),
                  case let .rebound(kept, removed)? = try? await RootRebinder().rebind(folderID: folder.id, to: target,
                                                                                       in: store) else { continue }
            let name = (folder.path as NSString).lastPathComponent
            moved.append(MovedFolder(id: folder.id, said: .init(folderName: name, kept: kept, removed: removed)))
        }
        return (outcome, moved)
    }
}
