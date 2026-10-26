import Foundation
import LibraryScan
import LibraryStore

// MARK: - LibraryModel library-scan seam (S8.2b — was AudioViewModel+LibraryScan)

//
// The store-population path for adding a music folder. Adding a folder registers it and then
// WALKS it into the persistent library store (the browse UI reads the store); it never touches the
// play queue (S9 IA change — the queue is built by the Library's Play / Play Next / Add to Queue
// verbs).
//
// The walk is one of the folder walks `walkSchedule` runs (`LibraryModel+Walks`): one per folder at
// a time, one add at a time, so a second add waits for the first instead of cancelling it (S10.8 G,
// G-LIB-06). The heavy per-file walk runs OFF the main actor inside `LibraryScanner`'s
// `nonisolated` scan; `performAddWalk` itself is `@MainActor` (extension inheritance) and only
// publishes results there — so just `Sendable` types cross. Cancellation (removing the folder,
// quitting) makes `LibraryScanner`'s per-file `checkCancellation()` throw and SKIP its sweep (no
// wrongful delete). The add's metadata pass then runs on `scanTask`.

extension LibraryModel {
    /// Construct the persistent store at `location` off-main at init (design §7). Failure is
    /// non-fatal: `store` stays nil, the audio path is untouched, and a note is surfaced.
    /// Called from `init`'s Task so the async initializer never blocks the main actor.
    func makeLibraryStore(at location: AppDataLocation) async {
        do {
            let url = location.storeURL
            let created = try await LibraryStore(url: url, appBuild: appBuildIdentifier)
            store = created
            // A quarantine-rebuild means the on-disk DB was damaged and reset — and it held
            // user data (playlists + play history) a rebuild can't recover. Surface it (don't wipe
            // in silence, S10.3 break-it); the derived library re-populates on the next scan.
            if let quarantined = created.quarantinedFrom {
                onError?("Your library database was damaged and was reset. Playlists and play "
                    + "history couldn't be recovered. The previous file was saved to "
                    + "\(quarantined.path).")
            }
            // The cache creates its folder on its first write.
            metadataArtworkCache = ArtworkCache(directory: location.artworkCacheURL)
            logUX("libraryStore: ready at '\(Self.makeDisplayPath(url))'")
            onStoreReady?() // S10.2 2c: store is live — let the audio VM hydrate the queue
            isStoreOpening = false // files opened meanwhile go on, matched to the library
        } catch {
            // Additive seam — the app runs without the store; only the parallel
            // store-population is unavailable until the next successful construction. Say why: a
            // library the store refused is left as it was, and the user should know it's safe.
            logUX("libraryStore: init failed — \(error)")
            onError?(Self.storeOpenFailureMessage(error))
            isStoreOpening = false // files opened meanwhile play, as files from outside the library
        }
        // S8.4: start the FSEvents watcher — it drives the live store reconcile.
        // refreshWatchedRoots picks up the store roots.
        startLibraryWatcher()
        await refreshWatchedRoots()
        startVolumeMonitor() // NSWorkspace mount/unmount → pause/resume + remount re-stamp (5b)
        #if DEBUG
            // Test library (`-ASTestLibrary <folder>`, Debug/TestLibrary.swift): add its music folder
            // on every launch. An exact root re-adds as a no-op, so a re-run only picks up changes.
            // Registered BEFORE the catch-up, which then finds its walk under way and adds none (no
            // start-then-cancel); its own metadata pass reads every pending song, so it stands in for
            // the launch re-read below.
            if let folder = location.testMusicFolder {
                scanFolderIntoLibrary(folder)
                await folderAddTask?.value
                await catchUpLibraryFolders()
                return
            }
        #endif
        await catchUpLibraryFolders()
        if let store {
            let reason = store.derivedDataRefreshed
                ? "full re-read for derived data v\(LibraryStore.derivedDataVersion)" : "resuming an interrupted pass"
            await readPendingTags(store, reason: reason)
        }
    }

    /// Read the tags of songs added to a playlist from outside the library (R1.1-B, US-PLIST-02): their
    /// rows wait for them (`tracks.metadata_scanned = 0`) like any new song. A library-wide pass reads
    /// every pending song, so it supersedes the one running, as a folder add's does
    /// (`startFullMetadataPass`); with nothing else pending it reads just these.
    func readPendingTags() {
        guard let store else { return }
        Task {
            guard let generation = try? await store.beginScanGeneration() else { return }
            logUX("libraryStore: reading the tags of songs added from outside the library")
            startFullMetadataPass(store, generation: generation)
        }
    }

    /// Read the tags of songs left pending at launch (S10.8 C2): the one-time full re-read a
    /// derived-data version bump queues (`LibraryStore.derivedDataRefreshed`), or a pass cut off
    /// at quit — including one cut off after its last song but before its end-of-pass album
    /// regroup (`isAlbumRegroupOwed`, C2 fix round B2). Without this they would wait for the next
    /// folder change. Runs after the launch catch-up, whose reconciles read their own folders'
    /// pending songs, so it reads only what they left (never the same song twice). Runs on
    /// `scanTask`, so a folder add's pass (which reads every pending song) supersedes it, and
    /// quitting cancels it. The sidebar shows "Reading tags…" while it runs; the Albums grid
    /// reloads when it ends.
    private func readPendingTags(_ store: LibraryStore, reason: String) async {
        let pending = (try? await store.tracksNeedingMetadata(limit: 1)) ?? []
        let regroupOwed = (try? await store.isAlbumRegroupOwed()) ?? false
        guard !pending.isEmpty || regroupOwed, let generation = try? await store.beginScanGeneration() else { return }
        // A folder added meanwhile owns `scanTask` now, and its pass reads every pending song and
        // regroups — never overwrite (and so orphan, uncancellable) it (B3).
        guard scanTask == nil else { return }
        logUX("libraryStore: reading pending tags (\(reason))")
        scanTask = Task(priority: .utility) { [weak self] in
            await self?.runMetadataPass(store, generation: generation)
        }
    }

    /// Add `url` to the persistent library store (the browse UI's source of truth): validate it
    /// FIRST (a nested/overlapping root is rejected via `onError`, and nothing else is touched),
    /// register it, then ask for its walk — which waits for any add walking another folder, never
    /// cancels it (S10.8 G, G-LIB-06). Adds register one at a time, in order (`folderAddTask`), so
    /// each is validated against the folders registered before it.
    ///
    /// Never touches the play queue (S9 IA change) — adding a folder only scans.
    func scanFolderIntoLibrary(_ url: URL) {
        guard store != nil else {
            logUX("scanFolderIntoLibrary: store not ready; skipping (playlist unaffected)")
            return
        }
        let earlier = folderAddTask
        folderAddTask = Task { @MainActor [weak self] in
            await earlier?.value
            await self?.registerLibraryFolder(url)
        }
    }

    /// Validate `url` against the registered roots, register it (the root's on-disk (dev,inode)
    /// dedups a case-variant path for the same directory on a case-insensitive volume, QS3), cover
    /// it with the FSEvents watcher, and ask for its add walk.
    private func registerLibraryFolder(_ url: URL) async {
        guard let store else { return }
        // Hold security-scoped access while registering — the validation and the (dev,inode) read
        // touch `url`. Inert under the Developer-ID posture (returns false); correct once sandbox
        // bookmarks land (S8.4). The walk reads the root by its stored path, like a reconcile.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let existing = try await store.roots().map { URL(fileURLWithPath: $0.path) }
            try LibraryScanner().validateNewRoot(url, against: existing)
            let identity = RootReachabilityProbe.identity(of: url)
            let folderID = try await store.addRoot(url, dev: identity?.dev, inode: identity?.inode,
                                                   volume: identity?.volume)
            await refreshWatchedRoots() // cover the newly registered root with the watcher (S8.4)
            requestWalk(.add, of: folderID)
        } catch let conflict as NestedRootConflict {
            publishScanRejection(conflict)
        } catch {
            onError?("Library scan failed: \(error.localizedDescription)")
            logUX("scanFolderIntoLibrary: registering '\(Self.makeDisplayPath(url))' FAILED — \(error)")
        }
    }

    /// Remove a registered library root. Deletes its store rows (tracks → orphaned albums/
    /// artists/genres are swept), so browse drops the folder's content — but the audio files on
    /// disk and the in-memory QUEUE are untouched: the queue is URL-keyed and not a store
    /// reference, so a queued or currently-playing track from this folder keeps playing. Stops
    /// every walk of the root BEFORE the delete so a late walk can't re-insert its rows (design §5
    /// / AC-14), then re-points the FSEvents watcher and bumps `libraryRevision`. ADDITIVE: never
    /// touches the play queue/engine (those live on the audio VM).
    func removeLibraryFolder(id folderID: Int64) async {
        guard let store else { return }
        // Stop walking THIS folder before deleting its row — drop a pending debounce and a waiting
        // walk, and cancel + await its running walk (an add's or a reconcile's): otherwise the
        // walk's next batch UPSERTs a now-dangling folder_id → FK failure + a spurious "scan failed"
        // error + wasted work (AC-14, review 1b). A library-wide METADATA pass running meanwhile
        // (`scanTask`: the launch re-read, or an add's pass) is left running: it skips every song
        // whose row the delete removes (`applyExtractedResult` writes nothing for a gone row —
        // S10.8 C2 fix round, B3) and its end-of-pass regroup settles the rest.
        reconcileDebounce[folderID]?.cancel()
        reconcileDebounce[folderID] = nil
        walkSchedule.beginRemoving(folderID)
        if let walk = walkTasks[folderID] {
            walk.cancel()
            await walk.value
        }
        reconcileState[folderID] = nil
        do {
            try await store.removeRoot(id: folderID)
            walkSchedule.endRemoving(folderID)
            await refreshWatchedRoots() // drop the removed root from the FSEvents watch set
            libraryRevision &+= 1 // browse reloads and drops the folder's albums/songs
            logUX("removeLibraryFolder: removed root \(folderID)")
        } catch {
            walkSchedule.endRemoving(folderID)
            onError?("Couldn't remove folder: \(error.localizedDescription)")
            logUX("removeLibraryFolder: FAILED for root \(folderID) — \(error)")
            requestWalk(.reconcile, of: folderID) // it stays; its stopped walk is owed a re-run
        }
    }

    /// The walk that follows registering a folder (`walkSchedule` runs it as the folder's walk): walk
    /// the root by its stored path into the store, publishing progress, then hand the walk's
    /// generation to the library-wide metadata pass. Runs on the main actor (extension inheritance)
    /// but AWAITS `LibraryScanner`'s `nonisolated` walk, so the heavy per-file work executes off the
    /// main actor. Errors are surfaced via `onError`; a `CancellationError` is silent (removing the
    /// folder, quitting), leaving committed batches valid.
    func performAddWalk(_ root: WatchedRoot, store: LibraryStore) async {
        // Hold security-scoped access across the walk. Inert under the Developer-ID posture (returns
        // false); correct once sandbox bookmarks land (S8.4) — the same as a reconcile.
        let didAccess = root.url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                root.url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let result = try await LibraryScanner().scan(
                root: root.url, folderID: root.folderID, into: store,
                progress: { [weak self] snapshot in
                    Task { @MainActor in self?.scanProgress = snapshot }
                }
            )
            publishScanResult(result)
            reconcileState[root.folderID] = walkedState(of: root.url)
            // After the structural scan (NOT inline — locked decision): enrich new/changed rows
            // with tags + art, reusing this walk's generation. The pass ends by regrouping albums +
            // reaping orphan facets (SF-2, S10.8 C2) — no separate sweep here.
            startFullMetadataPass(store, generation: result.generation)
        } catch is CancellationError {
            scanProgress = nil
        } catch let refusal as SweepRefusal {
            scanProgress = nil
            pause(refusedBy: refusal, in: "performAddWalk")
        } catch {
            scanProgress = nil
            onError?("Library scan failed: \(error.localizedDescription)")
        }
    }

    /// Start the library-wide metadata pass on `scanTask`, superseding the one running (the launch
    /// re-read, or an earlier add's): this pass reads every pending song too, so the older one is
    /// cancelled and awaited first — two full passes never read the same songs at once.
    private func startFullMetadataPass(_ store: LibraryStore, generation: Int64) {
        let superseded = scanTask
        superseded?.cancel()
        scanTask = Task(priority: .utility) { [weak self] in
            await superseded?.value
            await self?.runMetadataPass(store, generation: generation)
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

    /// Surface a nested/overlapping-root rejection on the main actor (design §6, O-2). Nothing was
    /// registered, and a walk of another folder carries on.
    @MainActor
    private func publishScanRejection(_ conflict: NestedRootConflict) {
        let relation = conflict.kind == .descendantOfExisting ? "inside" : "contains"
        onError?("Folder \(relation) an existing library folder — "
            + "'\(conflict.newRoot)' overlaps '\(conflict.existingRoot)'")
        logUX("scanFolderIntoLibrary: rejected nested root \(conflict.kind) "
            + "(new='\(conflict.newRoot)' existing='\(conflict.existingRoot)')")
    }

    /// The note for a library that didn't open (S10.8 C2). A `StoreOpenRefusal` left the file as it
    /// was, so the note says the user's data is safe and what to do next.
    private static func storeOpenFailureMessage(_ error: any Error) -> String {
        switch error as? StoreOpenRefusal {
        case .newerVersion:
            "This library was last opened by a newer version of AdaptiveSound, so this version can't "
                + "open it. Nothing was changed — open it with the newer version."
        case let .backupFailed(cause):
            "AdaptiveSound couldn't make a safety copy of your library before updating it, so it left "
                + "the library as it was. Check that your disk has free space, then reopen the app. "
                + "(\(cause.localizedDescription))"
        case let .openFailed(cause):
            "Your library couldn't be opened (\(cause.localizedDescription)). Nothing was deleted — "
                + "your playlists and play history are safe. Reopen the app to try again."
        case .unfinishedTestVersion:
            "This library was opened by an unfinished test version of AdaptiveSound and can't be used. "
                + "Nothing was changed. Reset the test library, or restore a backup."
        case nil:
            "Your library couldn't be opened (\(error.localizedDescription))."
        }
    }
}

/// The build identifier stamped into the store's `schema_info.app_build`. Kept here
/// (not a magic string in `makeLibraryStore`) so it has one home in the scan seam.
private let appBuildIdentifier = "adaptivesound"
