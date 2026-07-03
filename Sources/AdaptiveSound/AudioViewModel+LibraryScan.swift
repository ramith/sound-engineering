import Foundation
import LibraryScan
import LibraryStore

// MARK: - AudioViewModel library-scan seam (S8.2b — ADDITIVE)

//
// The store-population half of Choose-Folder. It runs ALONGSIDE `loadMusicFolder`
// (design §7): the in-memory `playlist` still comes from `loadMusicFolder` (unchanged
// UX) while this fills the persistent store in parallel. The UI's source swaps to
// store-reads at S9. Folder-monitor → store rewiring is S8.4 — NOT here.
//
// Shape mirrors `loadMusicFolder`: a `Task` retained in `scanTask` drives the scan.
// The heavy per-file walk runs OFF the main actor inside `LibraryScanner`'s
// `nonisolated` scan; `performScan` itself is `@MainActor` (extension inheritance) and
// only publishes results there — so just `Sendable` types cross. Cancellation: a
// re-trigger (which reassigns `scanTask`, cancelling the prior) or teardown
// (`shutdown()`) cancels it, making `LibraryScanner`'s per-file `checkCancellation()`
// throw and SKIP its sweep (no wrongful delete).

extension AudioViewModel {
    /// Construct the persistent store off-main at init (design §7). Failure is
    /// non-fatal: `store` stays nil, the in-memory playlist path is untouched, and a
    /// note is surfaced. Called from `init`'s Task so the async initializer never
    /// blocks the main actor.
    func makeLibraryStore() async {
        do {
            let url = try LibraryStore.defaultStoreURL()
            let created = try await LibraryStore(url: url, appBuild: appBuildIdentifier)
            store = created
            if let cacheURL = try? LibraryStore.defaultArtworkCacheURL() {
                metadataArtworkCache = ArtworkCache(directory: cacheURL)
            }
            logUX("libraryStore: ready at '\(Self.makeDisplayPath(url))'")
        } catch {
            // Additive seam — the app runs without the store; only the parallel
            // store-population is unavailable until the next successful construction.
            logUX("libraryStore: init failed — \(error.localizedDescription)")
        }
        // S8.4: start the FSEvents watcher regardless of the store outcome — it drives the
        // visible playlist refresh (store-independent) AND, when the store exists, the live
        // reconcile. refreshWatchedRoots picks up the store roots (∪ the visible folder).
        startLibraryWatcher()
        await refreshWatchedRoots()
        startVolumeMonitor() // NSWorkspace mount/unmount → pause/resume + remount re-stamp (5b)
        // Network roots have no FSEvents live-watch — reconcile them once at launch (D2 split).
        for root in networkRoots {
            scheduleReconcile(folderID: root.folderID, root: root.url)
        }
    }

    /// Scan `url` INTO the persistent library store, in parallel with the in-memory
    /// playlist (design §7). Cancels any prior scan, then off-main: reject nested/
    /// overlapping roots (surfaced via `errorMessage`), `addRoot`, then walk +
    /// reconcile with a progress closure that hops to `@MainActor` to publish state.
    ///
    /// ADDITIVE: does NOT touch `loadMusicFolder`/`playlist`/the folder monitor.
    func scanFolderIntoLibrary(_ url: URL) {
        // Cancel a prior in-flight scan (re-trigger) before starting the next — the
        // old scanner observes cancellation per file and skips its sweep.
        scanTask?.cancel()
        scanProgress = nil
        guard let store else {
            logUX("scanFolderIntoLibrary: store not ready; skipping (playlist unaffected)")
            return
        }
        // A plain `Task` (not `.detached`): the heavy walk is already off-main inside
        // `LibraryScanner`'s `nonisolated` scan, so detachment buys nothing here.
        scanTask = Task(priority: .utility) { [weak self] in
            await self?.performScan(url, store: store)
        }
    }

    /// Validates the root, registers it, then walks + reconciles. Runs on the main
    /// actor (extension inheritance) but AWAITS `LibraryScanner`'s `nonisolated` walk,
    /// so the heavy per-file work executes off the main actor; progress + the final
    /// result are published on the main actor. Errors are surfaced via `errorMessage`;
    /// a `CancellationError` is silent (an expected re-trigger/teardown), leaving
    /// committed batches valid.
    private func performScan(_ url: URL, store: LibraryStore) async {
        // Hold security-scoped access across the whole scan — the walk reads files
        // under `url`. Inert under the Developer-ID posture (returns false); correct
        // once sandbox bookmarks land (S8.4). Per-process, so it covers the off-main
        // walk, and this scan owns its own scope independent of the view's Task.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let existing = try await store.roots().map { URL(fileURLWithPath: $0.path) }
            try LibraryScanner().validateNewRoot(url, against: existing)
            // Pass the root's on-disk (dev,inode) so addRoot dedups a case-variant path
            // for the same directory on a case-insensitive volume (QS3).
            let signature = LibraryScanner.deviceInode(of: url)
            let folderID = try await store.addRoot(url, dev: signature.dev, inode: signature.inode)
            // Cover the newly registered root with the live FSEvents watcher (S8.4).
            await refreshWatchedRoots()
            let result = try await LibraryScanner().scan(
                root: url, folderID: folderID, into: store,
                progress: { snapshot in
                    Task { @MainActor [weak self] in self?.scanProgress = snapshot }
                }
            )
            publishScanResult(result)
            // After the structural scan (NOT inline — locked decision): enrich new/changed
            // rows with tags + art, reusing this scan's generation. Runs on the same
            // `scanTask`, so a re-trigger/teardown cancels the pass too.
            await runMetadataPass(store, generation: result.generation)
            // Post-churn facet cleanup (SF-2): reap albums/artists/genres a re-scan's deletes
            // orphaned. Non-cancelled only (matches the artwork-sweep posture).
            if !Task.isCancelled { _ = try? await store.sweepOrphanFacets() }
        } catch is CancellationError {
            await MainActor.run { [weak self] in self?.scanProgress = nil }
        } catch let unreachable as RootUnreachableError {
            // Empty-walk safety guard tripped (unmounted/zombie volume or deleted root): the
            // rows are preserved, NOT swept. Silent like cancellation — a background non-event.
            logUX("performScan: root unreachable (folder \(unreachable.folderID); "
                + "\(unreachable.storedRowCount) rows preserved) — sweep refused")
            await MainActor.run { [weak self] in self?.scanProgress = nil }
        } catch let conflict as NestedRootConflict {
            publishScanRejection(conflict)
        } catch {
            await MainActor.run { [weak self] in
                self?.scanProgress = nil
                self?.errorMessage = "Library scan failed: \(error.localizedDescription)"
            }
        }
    }

    /// Publish a completed scan's result on the main actor + clear live progress.
    @MainActor
    private func publishScanResult(_ result: ScanResult) {
        lastScanResult = result
        scanProgress = nil
        logUX("scanFolderIntoLibrary: done — seen=\(result.filesSeen) skipped=\(result.filesSkipped) "
            + "swept=\(result.orphansSwept)")
    }

    /// Surface a nested/overlapping-root rejection on the main actor (design §6, O-2).
    @MainActor
    private func publishScanRejection(_ conflict: NestedRootConflict) {
        scanProgress = nil
        let relation = conflict.kind == .descendantOfExisting ? "inside" : "contains"
        errorMessage = "Folder \(relation) an existing library folder — "
            + "'\(conflict.newRoot)' overlaps '\(conflict.existingRoot)'"
        logUX("scanFolderIntoLibrary: rejected nested root \(conflict.kind) "
            + "(new='\(conflict.newRoot)' existing='\(conflict.existingRoot)')")
    }
}

/// The build identifier stamped into the store's `schema_info.app_build`. Kept here
/// (not a magic string in `makeLibraryStore`) so it has one home in the scan seam.
private let appBuildIdentifier = "adaptivesound"
