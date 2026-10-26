import Foundation
import LibraryBrowseKit
import LibraryScan
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

    /// The playlist whose page is open, or nil.
    private(set) var openPlaylistID: Int64?
    /// The open playlist's rows. Each change re-checks an open Remove Missing confirmation against
    /// the entries still missing (`PlaylistDialogLatch.missingChanged`) — only while one is up, so a
    /// reload doesn't write (and so re-publish) the dialog for nothing.
    private(set) var detail: [PlaylistDetailEntry] = [] {
        didSet {
            if case .confirmRemoveMissing = dialogs.dialog {
                dialogs.missingChanged(to: Set(missingEntryIDs))
            }
        }
    }

    private(set) var detailState: LoadState = .idle
    private var detailEpoch = 0
    /// Saves each playlist's newest on-screen order, one write at a time (E4: `reorderEntries`).
    @ObservationIgnored private let orderWriter: CoalescingWriter<Int64, [Int64]>
    /// The failed save behind a failure notice, so a later successful save of that playlist withdraws it.
    @ObservationIgnored private var orderFailure: (playlistID: Int64, message: String)?

    /// The Library tab's one playlist dialog (S10.8 E fix round): a per-ACTION failure's notice —
    /// never routed through `detailState` (a failed row-action mustn't blow the whole pane into
    /// load-error; F review) — or the Remove Missing confirmation. One latched value, moved only by
    /// the verbs under "Dialogs" below, and shown once, by `LibraryTabView`'s sheet.
    private var dialogs = PlaylistDialogLatch()

    /// The `library.libraryRevision` last folded in, so `reloadOnLibraryChange` refreshes exactly
    /// once per library-content change (a track deletion CASCADE-drops entries → counts move).
    private var lastLoadedRevision = 0

    init(library: LibraryModel, audio: AudioViewModel) {
        self.library = library
        self.audio = audio
        // The sink reaches the model weakly; `self` exists only once every stored property is set.
        weak var model: PlaylistsModel?
        orderWriter = CoalescingWriter { playlistID, order in await model?.saveOrder(order, of: playlistID) }
        model = self
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
        if playlists.isEmpty {
            treeState = .loading
        }
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
        if let id = openPlaylistID {
            await loadDetail(id: id)
        }
    }

    // MARK: - Playlist lifecycle (create / rename / delete)

    /// Create a new "New Playlist"-style untitled playlist, reload, and return its id so the sidebar
    /// can select it and drop straight into inline-rename. Nil if the store isn't ready or the
    /// create failed (said in the failure notice).
    @discardableResult
    func createPlaylist() async -> Int64? {
        guard let store else { return nil }
        do {
            let id = try await store.createUntitledPlaylist()
            await loadTree()
            return id
        } catch {
            fail("Couldn’t create a playlist: \(error.localizedDescription)")
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

    /// Delete a playlist (`confirmDelete`). Built-in deletion never reaches here (filtered). RETURNS
    /// whether the delete succeeded, so the caller only redirects nav on success: a failed delete
    /// leaves the row, says so in the failure notice, and nav must not jump away.
    ///
    /// On success its row leaves the rail and its open detail closes AT ONCE (so a stale detail can't
    /// linger after its playlist is gone), with no suspension before the return — the caller leaves
    /// the page in the same main-actor turn, and no frame shows the page closed (its "Playlist" title
    /// over a spinner). The tree is then re-read behind, to confirm.
    private func deletePlaylist(id: Int64) async -> Bool {
        guard let store else { return false }
        do {
            try await store.deletePlaylist(id: id)
        } catch {
            fail("Couldn’t delete \(quotedName(of: id)): \(error.localizedDescription)")
            return false
        }
        playlists.removeAll { $0.id == id }
        if playlists.isEmpty {
            treeState = .empty
        }
        if openPlaylistID == id {
            closeDetail()
        }
        Task { await loadTree() }
        return true
    }

    // MARK: - Add to playlist (US-PLIST-02 — reference-add, never a file move)

    /// Append tracks (by id — a REFERENCE-add, never a file move/copy) to a playlist, de-duplicating
    /// the incoming selection. Reloads the tree (count badge) + the open detail if it's the target.
    /// Returns the number appended so the caller can raise a truthful toast.
    @discardableResult
    func addTracks(_ trackIDs: [Int64], toPlaylist playlistID: Int64) async -> Int {
        await add(trackIDs.map(PlaylistAddItem.track), toPlaylist: playlistID)
    }

    /// Create a new untitled playlist containing `trackIDs` (the "New Playlist" add path) and reload.
    /// Returns the new playlist — its id, so the sidebar can select it (+ drop into rename), and how many
    /// songs went in, for the toast. De-dupes the selection.
    @discardableResult
    func createPlaylist(withTracks trackIDs: [Int64]) async -> NewPlaylist? {
        await createPlaylist(with: trackIDs.map(PlaylistAddItem.track))
    }

    // MARK: - Detail loading

    /// Load a playlist's entries in position order, resolving each to its library track. An entry
    /// whose track is unresolved carries a nil `display` (F renders the unavailable state; B just
    /// shows the resolved rows). Epoch-guarded; the same loaded `detail` is what Chunk C acts on.
    func loadDetail(id: Int64) async {
        // Switching playlists: drop the previous rows so they can't linger under the NEW header/count
        // while the read is in flight (the header reads `openPlaylist`/`detail.count` immediately).
        if id != openPlaylistID {
            detail = []
        }
        openPlaylistID = id
        detailEpoch &+= 1
        let epoch = detailEpoch
        if detail.isEmpty {
            detailState = .loading
        }
        // No store (the launch build, or the picture-sheet fixture): an empty detail already shows
        // loading, and rows already on screen stay, as every store-backed loader leaves them.
        guard let store else { return }
        do {
            let entries = try await store.entries(inPlaylist: id)
            let byID = try await store.tracksDisplay(ids: entries.map(\.trackID))
            // Availability is a disk look per row — resolve it OFF the main actor so a large playlist
            // doesn't jank (F). A file not there is "missing" only on its own drive (KI-LIB-01).
            let availability = try await Self.entryAvailability(entries: entries, displays: byID, store: store)
            guard epoch == detailEpoch else { return } // a newer open/reload superseded this one
            let rows = entries.map {
                PlaylistDetailEntry(entry: $0, display: byID[$0.trackID],
                                    availability: availability[$0.id] ?? .missing)
            }
            // An order not saved yet is laid over what was read (E4): this read may predate its
            // write, and publishing the stored order would undo moves already on screen — and the
            // next move, planned from it, would save that undo.
            detail = ListOrder.applying(orderWriter.unsavedValue(for: id) ?? [], to: rows, id: \.id)
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

    // Play verbs (`playPlaylist`, `shufflePlaylist`, …) are in `PlaylistsModel+Play` — file length.

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
            // A per-action notice, never the pane-wide load error (F review): the rows are unchanged.
            fail("Couldn’t remove the song from \(quotedName(of: playlistID)): \(error.localizedDescription)")
        }
    }

    // Reorder (`reorderEntries`) is in the same-file extension below — type-body length.

    // MARK: - Dialogs (S10.8 E fix round — one latched value, `PlaylistDialogLatch`)

    /// The dialog the Library tab's sheet shows now, or nil.
    var dialog: PlaylistDialog? {
        dialogs.dialog
    }

    /// A playlist action failed: its notice takes the sheet (dropping an open confirmation). Internal for
    /// the same-type `+Add` extension.
    func fail(_ message: String) {
        dialogs.fail(message)
    }

    /// The failure notice's OK.
    func dismissFailure() {
        dialogs.dismissFailure()
    }

    /// A confirmation's Cancel.
    func cancelConfirmation() {
        dialogs.cancel()
    }

    /// The rail's Delete… (its menu, or the Delete key): ask first — a deleted playlist can't be
    /// brought back.
    func askToDelete(_ playlist: Playlist) {
        dialogs.askToDelete(playlistID: playlist.id, name: playlist.name)
    }

    /// The delete confirmation's Delete: deletes the confirmed playlist, once. Returns its id when it
    /// was deleted — the caller then leaves its page, if that is the one showing — or nil (nothing
    /// confirmed; the delete failed, which the failure notice says).
    func confirmDelete() async -> Int64? {
        guard let playlistID = dialogs.confirmDelete() else { return nil }
        return await deletePlaylist(id: playlistID) ? playlistID : nil
    }

    /// The ⋯ menu's Remove Missing…: ask first (no undo — F review), for exactly the entries missing
    /// now. Not during a scan / metadata pass / reconcile, when files flicker "missing".
    func askToRemoveMissing() {
        dialogs.askToRemoveMissing(missingEntryIDs, isLibraryPopulating: isLibraryPopulating)
    }

    /// The confirmation's Remove (bulk "Remove missing", F): drops exactly the confirmed entries —
    /// the ones missing when it was asked, less any whose file has come back since — then reloads
    /// detail + tree. Never during a scan, and once per confirmation.
    func confirmRemoveMissing() async {
        guard let store, let playlistID = openPlaylistID,
              let entries = dialogs.confirmRemoveMissing(isLibraryPopulating: isLibraryPopulating) else { return }
        do {
            try await store.removeEntries(ids: entries, playlistID: playlistID)
            await loadDetail(id: playlistID)
            await loadTree()
        } catch {
            fail("Couldn’t remove the missing songs: \(error.localizedDescription)")
        }
    }

    /// "“Road Trip”" for a failure's message, or "the playlist" once its row is gone.
    func quotedName(of playlistID: Int64) -> String {
        playlists.first { $0.id == playlistID }.map { "“\($0.name)”" } ?? "the playlist"
    }

    // MARK: - Dead/missing-file handling (F)

    /// Locate: re-point a missing entry's TRACK to a user-chosen file, preserving the track id (so
    /// every playlist referencing it is fixed at once), then reload so it resolves. Reuses the
    /// id-preserving `moveTrack` seam; the file becomes loose (`folder_id = nil`) until a rescan
    /// re-associates it — a full metadata re-scan is out of F scope. A URL already owned by another
    /// track throws `URLConflict` (caught → said in the failure notice).
    func relocateEntry(_ entryID: Int64, to url: URL) async {
        guard let store, let playlistID = openPlaylistID,
              let trackID = detail.first(where: { $0.id == entryID })?.entry.trackID else { return }
        do {
            try await store.moveTrack(id: trackID, newURL: url, newFolderID: nil, newRelativePath: "")
            await loadDetail(id: playlistID)
        } catch is URLConflict {
            // The picked file is already another track's — a per-row failure, NOT a pane-wide error.
            fail("That file is already in your library under a different track.")
        } catch {
            fail("Couldn’t relocate the file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Reorder (C; S10.8 E4 — a drag and the Move commands)

/// Same-file extension (type-body length): it writes the model's private detail state.
extension PlaylistsModel {
    /// Reorder the open playlist to `orderedEntryIDs` — a drag, or a Move command. The rows move AT
    /// ONCE, by the store's own rule, so a held ⌥⌘↓ compounds from the order on screen; the order
    /// is then saved through `orderWriter`: per playlist only the newest is written, never after a
    /// newer one, and until it is written every re-read lays it over what it read (`loadDetail`).
    /// Count is unchanged, so the tree isn't reloaded.
    func reorderEntries(_ orderedEntryIDs: [Int64]) {
        guard let playlistID = openPlaylistID else { return }
        orderWriter.submit(orderedEntryIDs, for: playlistID)
        detail = ListOrder.applying(orderedEntryIDs, to: detail, id: \.id)
    }

    /// Saves every order still waiting — awaited at quit, before the library tears down, so the
    /// last order on screen is the one stored.
    func flushPendingOrders() async {
        await orderWriter.flush()
    }

    /// `orderWriter`'s sink: write one playlist's order, then re-read it if it is the open one.
    private func saveOrder(_ order: [Int64], of playlistID: Int64) async {
        guard let store else { return }
        do {
            try await store.reorderPlaylist(id: playlistID, entryIDsInOrder: order)
            withdrawOrderFailure(of: playlistID)
            // Re-read INSIDE the write: this re-read supersedes any older one that may have read
            // before the write, and until it has, the order still counts as unsaved for that one.
            if openPlaylistID == playlistID {
                await loadDetail(id: playlistID)
            }
        } catch {
            // A per-action notice (F review), never the pane-wide load error — naming the playlist,
            // since it may not be the one on screen. Re-read once this write has ENDED, so the
            // failed order is no longer laid over the read and the stored order shows again;
            // nothing was written, so any read is current.
            let name = quotedName(of: playlistID)
            let message = "Couldn’t save the new order of \(name): \(error.localizedDescription)"
            orderFailure = (playlistID, message)
            fail(message)
            if openPlaylistID == playlistID {
                Task { await loadDetail(id: playlistID) }
            }
        }
    }

    /// A save of `playlistID` succeeded: its earlier failure is moot, so its notice goes — unless
    /// another dialog has replaced it since.
    private func withdrawOrderFailure(of playlistID: Int64) {
        guard let failure = orderFailure, failure.playlistID == playlistID else { return }
        dialogs.withdrawFailure(failure.message)
        orderFailure = nil
    }
}

#if DEBUG
    extension PlaylistsModel {
        /// Picture-sheet renderer only (`Debug/SheetFixture+Playlist.swift`): show `fixture` in the rail
        /// and `open` as the open playlist with `rows`, without a store. Lives here because the tree and
        /// the detail have private setters.
        func seedRenderFixture(playlists fixture: [Playlist], open: Int64, rows: [PlaylistDetailEntry]) {
            playlists = fixture
            treeState = fixture.isEmpty ? .empty : .loaded
            openPlaylistID = open
            detail = rows
            detailState = rows.isEmpty ? .empty : .loaded
        }
    }
#endif
