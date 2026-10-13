import Foundation
import LibraryScan
import LibraryStore

// MARK: - LibraryModel folder walks (S10.8 G — G-LIB-01 / 05 / 06)

//
// Every walk of a music folder — an ADD (the walk after registering a folder, `LibraryModel+Scan`)
// or a RECONCILE (an FSEvents change, a volume mount, the launch catch-up, `LibraryModel+Reconcile`)
// — is asked of ONE schedule, `walkSchedule` (`FolderWalkSchedule`, pure and tested in
// LibraryBrowseKitTests): one walk per folder at a time, one add at a time, waiting walks in request
// order. Two walks of one folder at once let the later walk's sweep delete songs that are on disk
// (G-LIB-01; the store now also refuses to lower a stamp); adding a second folder cancelled the
// first one's walk (G-LIB-06); nothing caught a folder up with what changed while the app was closed
// (G-LIB-05). This file starts what the schedule returns, holds each walk's task in `walkTasks`, and
// reports every walk's end back to it.

extension LibraryModel {
    /// Ask for a walk of `folderID`; it starts now, or once the walk it waits for ends.
    func requestWalk(_ walk: FolderWalk, of folderID: Int64) {
        startWalks(walkSchedule.request(walk, of: folderID))
    }

    /// Catch every registered folder up with what changed while the app was closed (G-LIB-05): the
    /// FSEvents stream starts at "now", so a song copied in or deleted while the app was closed would
    /// otherwise never show (or never leave) until something else changed in its folder. A reconcile
    /// of each root — cheap for unchanged files — except one already walking (the test library's own
    /// add). An unreachable root, or another drive at its path, is not walked: the scanner refuses it
    /// (`SweepRefusal`), the reconcile pauses it and its songs stay. Returns when those walks end, so
    /// the launch metadata pass that follows reads only the pending songs they left.
    ///
    /// Chosen over resuming the FSEvents stream from a saved event id: a full walk also covers network
    /// folders (no FSEvents), a volume changed on another Mac, and a purged or wrapped event history,
    /// through the one already-verified walk path; the event-id resume would only make it cheaper.
    func catchUpLibraryFolders() async {
        for root in watchedRoots {
            startWalks(walkSchedule.requestCatchUp(of: root.folderID))
        }
        for task in Array(walkTasks.values) {
            await task.value
        }
    }

    /// Start the walks the schedule returned, each as its folder's task in `walkTasks`.
    private func startWalks(_ starts: [FolderWalkSchedule.Start]) {
        for start in starts {
            walkTasks[start.folderID] = Task(priority: .utility) { @MainActor [weak self] in
                await self?.walk(start)
                self?.walkEnded(start.folderID, cancelled: Task.isCancelled)
            }
        }
        isReconciling = walkSchedule.isReconciling
    }

    /// Run one walk. Its root is read from the store, the source of truth — the cached
    /// `watchedRoots` can lag a concurrent refresh (a volume mounting while a folder is added) — and
    /// a folder that has left the library is not walked.
    private func walk(_ start: FolderWalkSchedule.Start) async {
        guard let store, let folder = try? await store.roots().first(where: { $0.id == start.folderID }) else {
            return
        }
        let root = WatchedRoot(folder)
        switch start.walk {
        case .add: await performAddWalk(root, store: store)
        case .reconcile: await performReconcile(folderID: root.folderID, root: root.url, store: store)
        }
    }

    /// A folder's walk ended: free its task, then start what was waiting for it (a cancelled walk is
    /// owed a reconcile, unless its folder is being removed or the library is shutting down).
    private func walkEnded(_ folderID: Int64, cancelled: Bool) {
        walkTasks[folderID] = nil
        startWalks(walkSchedule.finish(folderID, cancelled: cancelled))
    }
}
