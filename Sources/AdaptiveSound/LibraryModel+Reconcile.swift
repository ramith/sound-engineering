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
}

/// Per-root live reconcile state (coarse — for the S9 browse UI's reassurance affordance).
enum ReconcileState: Equatable {
    case watching // local volume, live-watched via FSEvents
    case onDemandOnly // network volume — no FSEvents; reconciles on-demand / at launch
    case paused // volume/folder currently unreachable
    case catchingUp // a reconcile is running
}

// MARK: - LibraryModel live folder-watch + reconcile seam (S8.4 slice 5a — was AudioViewModel+Reconcile)

//
// Replaces the old non-recursive DispatchSource monitor: ONE recursive FSEvents `LibraryWatcher`
// drives the persistent-store reconcile. On a filesystem change under a watched store root we
// debounce (~1 s), then re-scan that root into the store (reusing the already-verified
// LibraryScanner.scan → move-match → metadata → facet-sweep). The queue is NOT folder-bound
// (S9 IA change), so a disk change never rewrites it. The watcher's `@Sendable` sink hops to
// @MainActor FIRST (the SIGTRAP lesson) before touching any state.

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
        if let store { roots = (try? await store.roots()) ?? [] }
        let all = roots.map {
            WatchedRoot(folderID: $0.id, url: URL(fileURLWithPath: $0.path),
                        normalizedPath: PathNormalizer.normalizedString(forPath: $0.path))
        }
        watchedRoots = all
        var localURLs: [URL] = []
        var network: [WatchedRoot] = []
        for root in all {
            if isLocalVolume(root.url) {
                localURLs.append(root.url)
                if reconcileState[root.folderID] == nil { reconcileState[root.folderID] = .watching }
            } else {
                network.append(root)
                reconcileState[root.folderID] = .onDemandOnly
                logUX("watch: '\(root.url.lastPathComponent)' is on a network volume — FSEvents "
                    + "unavailable; reconciles on-demand + at launch only")
            }
        }
        networkRoots = network
        // Watch the store roots only. The queue is no longer folder-bound (S9 IA change), so
        // there is no visible-folder leg to add for a playlist refresh.
        libraryWatcher?.setRoots(localURLs)
    }

    /// Whether `url` is on a LOCAL volume (FSEvents can watch it). Unknown → assume local.
    func isLocalVolume(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? nil) ?? true
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
            if let root = watchedRoots.first(where: { $0.folderID == folderID }) {
                scheduleReconcile(folderID: folderID, root: root.url)
            }
        }
    }

    /// `path` is AT or UNDER `rootPath` (component-boundary; both already normalized).
    private func isPathUnder(_ path: String, _ rootPath: String) -> Bool {
        path == rootPath || PathNormalizer.isComponentBoundaryDescendant(path, of: rootPath)
    }

    /// Debounce (~1 s after the last event) → reconcile that root. Coalesces a burst.
    func scheduleReconcile(folderID: Int64, root: URL) {
        reconcileDebounce[folderID]?.cancel()
        reconcileDebounce[folderID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled, let self else { return }
            // Debounce fired — drop our own now-completed handle so the map doesn't accumulate
            // finished Tasks (S3 LOW-b). We are the current entry (not cancelled), and this runs
            // synchronously on the MainActor before runReconcile, so it can't wipe a newer schedule;
            // a re-run schedules a fresh handle via runReconcile's pendingReconcile path.
            self.reconcileDebounce[folderID] = nil
            await self.runReconcile(folderID: folderID, root: root)
        }
    }

    /// Gate on `reconcilingRoots` so same-root reconciles never overlap; a burst arriving mid-
    /// reconcile coalesces into ONE re-run afterward (the late change is not lost).
    private func runReconcile(folderID: Int64, root: URL) async {
        guard let store else { return }
        if reconcilingRoots.contains(folderID) { pendingReconcile.insert(folderID); return }
        reconcilingRoots.insert(folderID)
        isReconciling = true
        await performReconcile(folderID: folderID, root: root, store: store)
        reconcilingRoots.remove(folderID)
        isReconciling = !reconcilingRoots.isEmpty
        if pendingReconcile.remove(folderID) != nil { scheduleReconcile(folderID: folderID, root: root) }
    }

    /// Reconcile one already-registered root into the store (NO validate/addRoot preamble): the
    /// same scan → move-match → metadata → facet-sweep the on-demand path runs. Catches the
    /// empty-walk guard + cancellation silently (background non-events).
    private func performReconcile(folderID: Int64, root: URL, store: LibraryStore) async {
        // Proactive reachability precheck (slice 5b): an unmounted volume / deleted folder → skip
        // the walk entirely (paused). The empty-walk backstop (slice 3) remains the actual safety.
        guard RootReachabilityProbe.isReachable(root) else {
            reconcileState[folderID] = .paused
            logUX("reconcile: folder \(folderID) unreachable (volume/folder gone) — paused, rows preserved")
            return
        }
        reconcileState[folderID] = .catchingUp
        let didAccess = root.startAccessingSecurityScopedResource()
        defer { if didAccess { root.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await LibraryScanner().scan(root: root, folderID: folderID, into: store)
            await runMetadataPass(store, generation: result.generation)
            if !Task.isCancelled { _ = try? await store.sweepOrphanFacets() } // SF-2 post-churn cleanup
            reconcileState[folderID] = isLocalVolume(root) ? .watching : .onDemandOnly
            lastReconciledAt = Date()
            lastReconcileError = nil
            logUX("reconcile: folder \(folderID) — seen=\(result.filesSeen) swept=\(result.orphansSwept)")
        } catch is CancellationError {
            // expected on teardown / re-trigger
        } catch let unreachable as RootUnreachableError {
            reconcileState[folderID] = .paused
            logUX("reconcile: root unreachable (folder \(unreachable.folderID); "
                + "\(unreachable.storedRowCount) rows preserved) — sweep refused")
        } catch {
            lastReconcileError = error.localizedDescription
            logUX("reconcile: folder \(folderID) failed — \(error.localizedDescription)")
        }
    }
}
