import Foundation
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

    /// The `library.libraryRevision` last folded in, so `reloadOnLibraryChange` refreshes exactly
    /// once per library-content change (a track deletion CASCADE-drops entries → counts move).
    private var lastLoadedRevision = 0

    init(library: LibraryModel) {
        self.library = library
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
            // Built-in exclusion (is_builtin=0) — the "current" queue playlist is never a user row.
            let loaded = try await store.playlists().filter { !$0.isBuiltin }
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
    /// detail can't linger after its playlist is gone). Built-in deletion never reaches here (filtered).
    func deletePlaylist(id: Int64) async {
        guard let store else { return }
        do {
            try await store.deletePlaylist(id: id)
            if openPlaylistID == id { closeDetail() }
            await loadTree()
        } catch {
            treeState = .failed(error.localizedDescription)
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
            guard epoch == detailEpoch else { return } // a newer open/reload superseded this one
            detail = entries.map { PlaylistDetailEntry(entry: $0, display: byID[$0.trackID]) }
            detailState = detail.isEmpty ? .empty : .loaded
        } catch {
            guard epoch == detailEpoch else { return }
            detailState = .failed(error.localizedDescription)
        }
    }

    /// Drop the open detail (playlist deselected / deleted).
    func closeDetail() {
        openPlaylistID = nil
        detail = []
        detailState = .idle
    }

    /// The open playlist's row (for the detail header title/count), or nil.
    var openPlaylist: Playlist? {
        guard let openPlaylistID else { return nil }
        return playlists.first { $0.id == openPlaylistID }
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

    var id: Int64 {
        entry.id
    }
}
