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
// Shape mirrors `loadMusicFolder`: off-main work in a detached task, results
// published back on the VM's `@MainActor` isolation; only `Sendable` types cross.
// Cancellation: the detached scan `Task` is retained in `scanTask`; a re-trigger (or
// teardown) cancels it, which makes `LibraryScanner`'s per-file `checkCancellation()`
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
            logUX("libraryStore: ready at '\(Self.makeDisplayPath(url))'")
        } catch {
            // Additive seam — the app runs without the store; only the parallel
            // store-population is unavailable until the next successful construction.
            logUX("libraryStore: init failed — \(error.localizedDescription)")
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
        scanTask = Task.detached(priority: .utility) { [weak self] in
            await self?.performScan(url, store: store)
        }
    }

    /// The off-main scan body (a detached task). Validates the root, registers it,
    /// then walks + reconciles; progress + the final result are published on the main
    /// actor. Errors are surfaced via `errorMessage`; a `CancellationError` is silent
    /// (an expected re-trigger/teardown), leaving committed batches valid.
    private func performScan(_ url: URL, store: LibraryStore) async {
        do {
            let existing = try await store.roots().map { URL(fileURLWithPath: $0.path) }
            try LibraryScanner().validateNewRoot(url, against: existing)
            let folderID = try await store.addRoot(url)
            let result = try await LibraryScanner().scan(
                root: url, folderID: folderID, into: store,
                progress: { snapshot in
                    Task { @MainActor [weak self] in self?.scanProgress = snapshot }
                }
            )
            await publishScanResult(result)
        } catch is CancellationError {
            await MainActor.run { [weak self] in self?.scanProgress = nil }
        } catch let conflict as NestedRootConflict {
            await publishScanRejection(conflict)
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
