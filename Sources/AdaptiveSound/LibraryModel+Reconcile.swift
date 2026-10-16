import Foundation
import LibraryScan
import LibraryStore

// MARK: - Watched root

/// A store root the FSEvents watcher covers: its `folderID` + normalized path, so an event path
/// can be attributed back to the root that must be reconciled.
struct WatchedRoot: Equatable {
    let folderID: Int64
    let url: URL
    let normalizedPath: String

    /// The root for a registered `folder` (its stored, normalized path).
    init(_ folder: LibraryFolder) {
        folderID = folder.id
        url = URL(fileURLWithPath: folder.path)
        normalizedPath = PathNormalizer.normalizedString(forPath: folder.path)
    }
}

/// Per-root live reconcile state (coarse — the Music Folders row reads the pause and its reason).
enum ReconcileState: Equatable {
    case watching // local volume, live-watched via FSEvents
    case onDemandOnly // network volume — no FSEvents; reconciles at launch + on a volume change
    /// Its last walk was refused (`SweepRefusal`) for this reason — unreachable, another drive,
    /// unrecognized, unreadable or empty — so its songs are kept until a walk is evidence again.
    case paused(SweepRefusal.Reason)
    case catchingUp // a reconcile is running

    /// Why the folder is paused, or nil when it is not.
    var pauseReason: SweepRefusal.Reason? {
        if case let .paused(reason) = self {
            reason
        } else {
            nil
        }
    }
}

// MARK: - LibraryModel live folder-watch + reconcile seam (S8.4 slice 5a — was AudioViewModel+Reconcile)

//
// Replaces the old non-recursive DispatchSource monitor: ONE recursive FSEvents `LibraryWatcher`
// drives the persistent-store reconcile. On a filesystem change under a watched store root we
// debounce (~1 s), then ask the walk schedule for a reconcile of that root (`LibraryModel+Walks`:
// one walk per folder at a time), which re-scans it into the store (reusing the already-verified
// LibraryScanner.scan → move-match → metadata pass, which ends with the album regroup + facet
// sweep). The queue is NOT folder-bound (S9 IA change), so a disk change never rewrites it. The
// watcher's `@Sendable` sink hops to @MainActor FIRST (the SIGTRAP lesson) before touching any state.

extension LibraryModel {
    /// Build + start the FSEvents watcher (idempotent). Called once from `makeLibraryStore`.
    func startLibraryWatcher() {
        guard libraryWatcher == nil else { return }
        let watcher = LibraryWatcher(queue: libraryWatcherQueue) { [weak self] batch in
            // On the watcher's background queue — hop to @MainActor before touching VM state.
            Task { @MainActor [weak self] in self?.handleWatcherBatch(batch) }
        }
        libraryWatcher = watcher
        watcher.start()
    }

    /// Re-point the watcher at the current store roots (for reconcile). The queue is not
    /// folder-bound, so there is no visible-folder leg to watch (S9 IA change).
    func refreshWatchedRoots() async {
        var roots: [LibraryFolder] = []
        if let store {
            roots = (try? await store.roots()) ?? []
        }
        let all = roots.map(WatchedRoot.init)
        watchedRoots = all
        var localURLs: [URL] = []
        for root in all {
            if isLocalVolume(root.url) {
                localURLs.append(root.url)
                if reconcileState[root.folderID] == nil {
                    reconcileState[root.folderID] = .watching
                }
            } else {
                reconcileState[root.folderID] = .onDemandOnly
                logUX("watch: '\(root.url.lastPathComponent)' is on a network volume — FSEvents "
                    + "unavailable; reconciles at launch + on a volume change only")
            }
        }
        // Watch the store roots only. The queue is no longer folder-bound (S9 IA change), so
        // there is no visible-folder leg to add for a playlist refresh.
        libraryWatcher?.setRoots(localURLs)
    }

    /// Whether `url` is on a LOCAL volume (FSEvents can watch it). Unknown → assume local.
    func isLocalVolume(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? nil) ?? true
    }

    /// The state of a folder at `root` after a walk that was evidence (an add's or a reconcile's).
    func walkedState(of root: URL) -> ReconcileState {
        isLocalVolume(root) ? .watching : .onDemandOnly
    }

    /// Route one FSEvents batch (on @MainActor): reconcile each affected store root (debounced).
    /// The queue is not folder-bound (S9 IA change), so a disk change never rewrites it — only
    /// the library store reconciles.
    func handleWatcherBatch(_ batch: WatcherEventBatch) {
        var affected: Set<Int64> = []
        for event in batch.events {
            let path = PathNormalizer.normalizedString(forPath: event.path)
            for root in watchedRoots where isPathUnder(path, root.normalizedPath) {
                affected.insert(root.folderID)
            }
        }
        for folderID in affected {
            scheduleReconcile(folderID: folderID)
        }
    }

    /// `path` is AT or UNDER `rootPath` (component-boundary; both already normalized).
    private func isPathUnder(_ path: String, _ rootPath: String) -> Bool {
        path == rootPath || PathNormalizer.isComponentBoundaryDescendant(path, of: rootPath)
    }

    /// Debounce (~1 s after the last event) → ask for a reconcile of that root. Coalesces a burst;
    /// a reconcile asked for while the folder walks runs once after it (`walkSchedule`), so a late
    /// change is not lost and two walks of one folder never overlap.
    func scheduleReconcile(folderID: Int64) {
        reconcileDebounce[folderID]?.cancel()
        reconcileDebounce[folderID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled, let self else { return }
            // Debounce fired — drop our own now-completed handle so the map doesn't accumulate
            // finished Tasks (S3 LOW-b). We are the current entry (not cancelled), and this runs
            // synchronously on the MainActor, so it can't wipe a newer schedule.
            self.reconcileDebounce[folderID] = nil
            self.requestWalk(.reconcile, of: folderID)
        }
    }

    /// Reconcile one already-registered root into the store (NO validate/addRoot preamble): the
    /// same scan → move-match → metadata pass (album regroup + facet sweep) an add runs, with this
    /// root's own metadata pass. Runs as the root's walk (`LibraryModel+Walks`). Catches a refused
    /// sweep + cancellation silently (background non-events). The scanner decides whether the root is
    /// walked at all: an unmounted volume, a deleted folder or another drive at its path is not
    /// (`SweepRefusal`), and the root is paused with its rows preserved.
    func performReconcile(folderID: Int64, root: URL, store: LibraryStore) async {
        reconcileState[folderID] = .catchingUp
        let didAccess = root.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                root.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
            // The pass reads THIS root's pending songs only — a full pass (the launch re-read, a
            // folder add) may own the rest concurrently (S10.8 C2 fix round, B3) — and ends by
            // regrouping albums + reaping orphan facets (SF-2, S10.8 C2).
            await runMetadataPass(store, generation: result.generation, inFolder: folderID)
            reconcileState[folderID] = walkedState(of: root)
            lastReconciledAt = Date()
            lastReconcileError = nil
            logUX("reconcile: folder \(folderID) — seen=\(result.filesSeen) swept=\(result.orphansSwept)")
        } catch is CancellationError {
            // expected on teardown / re-trigger
        } catch let refusal as SweepRefusal {
            pause(refusedBy: refusal, in: "reconcile")
        } catch {
            lastReconcileError = error.localizedDescription
            logUX("reconcile: folder \(folderID) failed — \(error.localizedDescription)")
        }
    }

    /// A walk was not evidence of which of its folder's songs are gone (`SweepRefusal`: the folder
    /// vanished, is another drive or is unrecognized, or the walk was incomplete or empty): its rows are
    /// kept, and it is paused — with the reason, which its Music Folders row says — until a walk is
    /// evidence again. The one consequence for both kinds of walk (`walk` names it in the log); no alert
    /// or banner: a background non-event, shown only on its row.
    func pause(refusedBy refusal: SweepRefusal, in walk: String) {
        reconcileState[refusal.folderID] = .paused(refusal.reason)
        logUX("\(walk): sweep refused (folder \(refusal.folderID): \(refusal.reason); "
            + "\(refusal.storedRowCount) rows preserved) — paused")
    }
}
