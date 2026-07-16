import Foundation
import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - PlaylistsModel (S10.3 — the playlists view-model)

/// Owns the sidebar Playlists tree and the open-playlist detail, over the SAME store as the rest of
/// the library (`library.store` — the playlist DAO already lives there; D-store rev.5, one store).
/// `@MainActor` + `@Observable`, a composition-root peer of `LibraryBrowseModel` held as `@State` in
/// the `App` and injected via `.environment` — NOT `@State` in a view, because the tab area is a
/// `switch` that destroys the view on every tab change (would otherwise reset the loaded tree).
///
/// Per-surface epoch tokens (tree / detail) mirror `LibraryBrowseModel`'s newest-wins discipline;
/// every mutation authoritatively re-reads. NAV (which playlist is selected) lives on
/// `LibraryBrowseModel` (`path`/`SidebarSelection`), not here — this model is the data + verbs.
///
/// Scope note: this is the Chunk-B surface (flat list + create/rename/delete + read-only detail).
/// Play/remove/reorder verbs (+ the `audio` dependency) land in Chunk C; folders in Chunk D — added
/// alongside their UI consumers so nothing sits here as dead code under the hostile Periphery gate.
@MainActor
@Observable
final class PlaylistsModel {
    /// Per-surface load state (drives the sidebar/detail spinner / empty / error rendering).
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    /// The library subsystem this reads through (store + `libraryRevision`). A peer dependency, kept
    /// non-owning like `LibraryBrowseModel.library` (S3 F5 — the God-object split).
    let library: LibraryModel

    /// The playback VM the play verbs route through (Play/Next/Queue + restore-queue undo). Added in
    /// Chunk C alongside its UI consumers so it isn't a dead dependency.
    let audio: AudioViewModel

    // Sidebar tree (flat in B; folder rows join in D).
    private(set) var playlists: [Playlist] = []
    private(set) var treeState: LoadState = .idle
    /// Monotonic newest-wins token for `loadTree` (a slow read must not overwrite a newer one —
    /// create/rename/delete + a scan-reconcile all trigger reloads concurrently).
    private var treeEpoch = 0

    // Open-playlist detail (rendered read-only by `PlaylistDetailView` in B; Chunk C wires
    // play/remove/reorder onto the SAME loaded rows).
    private(set) var openPlaylistID: Int64?
    private(set) var detail: [PlaylistDetailEntry] = []
    private(set) var detailState: LoadState = .idle
    private var detailEpoch = 0

    /// A transient per-ACTION error (Locate / Remove-missing) shown as an alert — never routed through
    /// `detailState` (a failed row-action mustn't blow the whole pane into load-error; F review).
    private(set) var actionError: String?

    /// The `library.libraryRevision` last folded in, so `reloadOnLibraryChange` refreshes exactly
    /// once per library-content change (a track deletion CASCADE-drops entries → counts move).
    private var lastLoadedRevision = 0

    init(library: LibraryModel, audio: AudioViewModel) {
        self.library = library
        self.audio = audio
    }

    // MARK: - Store access

    /// The store once `LibraryModel` has finished building it (async at launch); nil early.
    var store: LibraryStore? {
        library.store
    }

    /// Whether the async-built store is ready — drives the initial tree load so a visit BEFORE the
    /// store finishes constructing isn't stuck on a spinner (same discipline as `LibraryBrowseModel`).
    var isStoreReady: Bool {
        library.store != nil
    }

    // MARK: - Tree loading

    /// Load the user playlists (built-in "current" excluded — it's invisible + inert, D-store). Sets
    /// `empty` when there are none, `failed` on error. Epoch-guarded; keeps the cached list on screen
    /// while refreshing so a reload never flashes empty.
    func loadTree() async {
        guard let store else {
            treeState = .loading // store still building; reloads on `isStoreReady`
            return
        }
        treeEpoch &+= 1
        let epoch = treeEpoch
        if playlists.isEmpty { treeState = .loading }
        do {
            // Built-in exclusion (the "current" queue playlist never appears) via the pure,
            // unit-tested `PlaylistBrowseVisibility` — not an inline filter (design §5).
            let all = try await store.playlists()
            let loaded = PlaylistBrowseVisibility.userVisible(all)
            guard epoch == treeEpoch else { return } // a newer load superseded this one
            playlists = loaded
            treeState = loaded.isEmpty ? .empty : .loaded
        } catch {
            guard epoch == treeEpoch else { return }
            treeState = .failed(error.localizedDescription)
        }
    }

    /// Refresh the tree + any open detail when a scan / metadata pass / reconcile changes library
    /// content (a deleted track CASCADE-drops its entries → entry counts move). Coalesced to
    /// `libraryRevision` — one reload per pass, mirroring `LibraryBrowseModel.reloadIfScanChanged`.
    func reloadOnLibraryChange() async {
        guard library.libraryRevision != lastLoadedRevision else { return }
        lastLoadedRevision = library.libraryRevision
        await loadTree()
        if let id = openPlaylistID { await loadDetail(id: id) }
    }

    // MARK: - Playlist lifecycle (create / rename / delete)

    /// Create a new "New Playlist"-style untitled playlist, reload, and return its id so the sidebar
    /// can select it and drop straight into inline-rename. Nil if the store isn't ready or the
    /// create failed (surfaced via `treeState`).
    @discardableResult
    func createPlaylist() async -> Int64? {
        guard let store else { return nil }
        do {
            let id = try await store.createUntitledPlaylist()
            await loadTree()
            return id
        } catch {
            treeState = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Rename a playlist and reload. THROWS on a duplicate name (`PlaylistNameConflict`) or an
    /// invalid/built-in target (`PlaylistMutationError`) so the inline-rename field can surface it
    /// and keep editing — the caller decides the message; the model just re-reads on success.
    func renamePlaylist(id: Int64, to name: String) async throws {
        guard let store else { return }
        try await store.renamePlaylist(id: id, to: name)
        await loadTree()
    }

    /// Delete a playlist and reload. Clears the open detail if it was the deleted one (so a stale
    /// detail can't linger after its playlist is gone). Built-in deletion never reaches here
    /// (filtered). RETURNS whether the delete succeeded, so the caller only redirects nav on success
    /// (a failed delete leaves the row + surfaces via `treeState`, and nav must not jump away).
    @discardableResult
    func deletePlaylist(id: Int64) async -> Bool {
        guard let store else { return false }
        do {
            try await store.deletePlaylist(id: id)
            if openPlaylistID == id { closeDetail() }
            await loadTree()
            return true
        } catch {
            treeState = .failed(error.localizedDescription)
            return false
        }
    }

    // MARK: - Add to playlist (US-PLIST-02 — reference-add, never a file move)

    /// Append tracks (by id — a REFERENCE-add, never a file move/copy) to a playlist, de-duplicating
    /// the incoming selection. Reloads the tree (count badge) + the open detail if it's the target.
    /// Returns the number appended so the caller can raise a truthful toast.
    @discardableResult
    func addTracks(_ trackIDs: [Int64], toPlaylist playlistID: Int64) async -> Int {
        let ids = PlaylistAddDecision.trackIDsToAdd(trackIDs)
        guard let store, !ids.isEmpty else { return 0 }
        do {
            let entryIDs = try await store.appendEntries(playlistID: playlistID, trackIDs: ids)
            await loadTree()
            if openPlaylistID == playlistID { await loadDetail(id: playlistID) }
            return entryIDs.count
        } catch {
            treeState = .failed(error.localizedDescription)
            return 0
        }
    }

    /// Create a new untitled playlist containing `trackIDs` (the "New Playlist" add path) and reload.
    /// Returns the new id so the sidebar can select it (+ drop into rename). De-dupes the selection.
    @discardableResult
    func createPlaylist(withTracks trackIDs: [Int64]) async -> Int64? {
        guard let store else { return nil }
        let ids = PlaylistAddDecision.trackIDsToAdd(trackIDs)
        do {
            let id = try await store.createUntitledPlaylist()
            if !ids.isEmpty { _ = try await store.appendEntries(playlistID: id, trackIDs: ids) }
            await loadTree()
            return id
        } catch {
            treeState = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Detail loading

    /// Load a playlist's entries in position order, resolving each to its library track. An entry
    /// whose track is unresolved carries a nil `display` (F renders the unavailable state; B just
    /// shows the resolved rows). Epoch-guarded; the same loaded `detail` is what Chunk C acts on.
    func loadDetail(id: Int64) async {
        // Switching playlists: drop the previous rows so they can't linger under the NEW header/count
        // while the read is in flight (the header reads `openPlaylist`/`detail.count` immediately).
        if id != openPlaylistID { detail = [] }
        openPlaylistID = id
        detailEpoch &+= 1
        let epoch = detailEpoch
        if detail.isEmpty { detailState = .loading }
        guard let store else {
            detailState = .loading
            return
        }
        do {
            let entries = try await store.entries(inPlaylist: id)
            let byID = try await store.tracksDisplay(ids: entries.map(\.trackID))
            // File-existence is a disk stat per row — resolve it OFF the main actor so a large
            // playlist doesn't jank (F). A resolved track whose file is gone = "unavailable".
            let availableIDs = await Self.availableEntryIDs(entries: entries, displays: byID)
            guard epoch == detailEpoch else { return } // a newer open/reload superseded this one
            detail = entries.map {
                PlaylistDetailEntry(entry: $0, display: byID[$0.trackID],
                                    isAvailable: availableIDs.contains($0.id))
            }
            detailState = detail.isEmpty ? .empty : .loaded
        } catch {
            guard epoch == detailEpoch else { return }
            detailState = .failed(error.localizedDescription)
        }
    }

    /// Drop the open detail (playlist deselected / deleted). Bumps `detailEpoch` so an IN-FLIGHT
    /// `loadDetail` (whose store read may have snapshotted the rows before the delete committed)
    /// can't resume and republish the gone playlist's rows into `detail` (QA break-it #1).
    func closeDetail() {
        detailEpoch &+= 1
        openPlaylistID = nil
        detail = []
        detailState = .idle
    }

    /// The open playlist's row (for the detail header title/count), or nil.
    var openPlaylist: Playlist? {
        guard let openPlaylistID else { return nil }
        return playlists.first { $0.id == openPlaylistID }
    }

    // MARK: - Play verbs (delegate to AudioViewModel; C)

    /// Playable entries of the open playlist, in order — the AVAILABLE ones (track resolved AND file
    /// on disk). Unavailable (missing-file) entries are SKIPPED on play, never halting (F); the UI
    /// still shows them, badged, with Locate / Remove.
    private var resolvedEntries: [PlaylistDetailEntry] {
        detail.filter(\.isAvailable)
    }

    private func playableFiles() -> [AudioFile] {
        resolvedEntries.compactMap(\.display).map { AudioFile($0) }
    }

    /// Play the open playlist NOW — REPLACES the queue, with a one-level "Restore previous queue"
    /// undo (D-play). Starts at `entryID` (a tapped row) or the top. Returns whether it actually
    /// replaced (false if nothing is playable) so the caller only raises the undo toast on a replace.
    @discardableResult
    func playPlaylist(startingAt entryID: Int64? = nil) -> Bool {
        let entries = resolvedEntries
        let files = entries.compactMap(\.display).map { AudioFile($0) }
        guard !files.isEmpty else { return false }
        let start = entryID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        audio.playNowWithUndo(files, startAt: start)
        return true
    }

    /// Insert the WHOLE open playlist's tracks right after the current one (header Play Next).
    @discardableResult
    func playPlaylistNext() -> Int {
        let files = playableFiles()
        guard !files.isEmpty else { return 0 }
        return audio.playNext(files)
    }

    /// Insert a SINGLE entry's track right after the current one (per-row "Play Next"). Returns count.
    @discardableResult
    func playEntryNext(_ entryID: Int64) -> Int {
        guard let display = resolvedEntries.first(where: { $0.id == entryID })?.display else { return 0 }
        return audio.playNext([AudioFile(display)])
    }

    /// Append the open playlist's tracks to the end of the queue (Add to Queue). Returns the count.
    @discardableResult
    func appendPlaylist() -> Int {
        let files = playableFiles()
        guard !files.isEmpty else { return 0 }
        return audio.appendToQueue(files)
    }

    /// Whether a "Restore previous queue" undo is available (a Play-replace happened).
    var canRestorePreviousQueue: Bool {
        audio.canRestorePreviousQueue
    }

    /// Restore the queue that a "Play" replaced (one-level undo).
    func restorePreviousQueue() {
        audio.restorePreviousQueue()
    }

    // MARK: - Entry mutation (C)

    /// Remove one entry from the open playlist, then reload the detail AND the tree (the sidebar
    /// count badge doesn't ride `libraryRevision`, so an entry mutation must reload it — design §8).
    func removeEntry(_ entryID: Int64) async {
        guard let store, let playlistID = openPlaylistID else { return }
        do {
            try await store.removeEntry(id: entryID, playlistID: playlistID)
            await loadDetail(id: playlistID)
            await loadTree()
        } catch {
            detailState = .failed(error.localizedDescription)
        }
    }

    /// Reorder the open playlist to `orderedEntryIDs` (dense renumber in the DAO), then reload the
    /// detail. Count is unchanged, so the tree isn't reloaded.
    func reorderEntries(_ orderedEntryIDs: [Int64]) async {
        guard let store, let playlistID = openPlaylistID else { return }
        do {
            try await store.reorderPlaylist(id: playlistID, entryIDsInOrder: orderedEntryIDs)
            await loadDetail(id: playlistID)
        } catch {
            detailState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Dead/missing-file handling (F)

    /// Remove ALL unavailable (missing-file) entries from the open playlist (bulk "Remove missing").
    /// Returns the count removed; reloads detail + tree.
    @discardableResult
    func removeMissingEntries() async -> Int {
        guard let store, let playlistID = openPlaylistID else { return 0 }
        let missing = detail.filter { !$0.isAvailable }.map(\.entry.id)
        guard !missing.isEmpty else { return 0 }
        do {
            try await store.removeEntries(ids: missing, playlistID: playlistID)
            await loadDetail(id: playlistID)
            await loadTree()
            return missing.count
        } catch {
            actionError = "Couldn’t remove the missing tracks: \(error.localizedDescription)"
            return 0
        }
    }

    func clearActionError() {
        actionError = nil
    }

    /// Locate: re-point a missing entry's TRACK to a user-chosen file, preserving the track id (so
    /// every playlist referencing it is fixed at once), then reload so it resolves. Reuses the
    /// id-preserving `moveTrack` seam; the file becomes loose (`folder_id = nil`) until a rescan
    /// re-associates it — a full metadata re-scan is out of F scope. A URL already owned by another
    /// track throws `URLConflict` (caught → surfaced via `detailState`).
    func relocateEntry(_ entryID: Int64, to url: URL) async {
        guard let store, let playlistID = openPlaylistID,
              let trackID = detail.first(where: { $0.id == entryID })?.entry.trackID else { return }
        do {
            try await store.moveTrack(id: trackID, newURL: url, newFolderID: nil, newRelativePath: "")
            await loadDetail(id: playlistID)
        } catch is URLConflict {
            // The picked file is already another track's — a per-row failure, NOT a pane-wide error.
            actionError = "That file is already in your library under a different track."
        } catch {
            actionError = "Couldn’t relocate the file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Detail row model

/// One row of an open playlist: its `PlaylistEntry` (the stable id + position — the reorder/remove
/// key Chunk C needs) plus the resolved library track, or nil when the track can't be resolved
/// (moved/deleted — Chunk F renders the "unavailable" state + Locate). `Identifiable` on the ENTRY
/// id (not the track) so duplicates of the same track in one playlist stay distinct rows.
struct PlaylistDetailEntry: Identifiable {
    let entry: PlaylistEntry
    let display: LibraryTrackDisplay?
    /// True when the track resolved AND its file exists on disk (S10.3 F). False = "unavailable":
    /// the file moved/was deleted (a loose file gone, or a move not yet reconciled) or the track row
    /// is absent — the row is badged, SKIPPED on play (never halts), and offered Locate / Remove.
    let isAvailable: Bool

    var id: Int64 {
        entry.id
    }
}
