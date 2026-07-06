import AppKit
import Foundation
import LibraryScan
import LibraryStore
import SwiftUI

// MARK: - LibraryBrowseModel (S9.4 — the browse view-model)

/// Owns all Library-tab browse state and is the single seam between the browse UI (reads +
/// selection) and `AudioViewModel` (playback + queue). `@Observable` + `@MainActor`, a peer
/// of `EQViewModel`. ★ Owned as `@State` in the `App` and injected via `.environment` — NOT
/// `@State` in `LibraryTabView`, because the tab area is a `switch` that destroys the view on
/// every tab change (design §2/§7), which would otherwise reset selection/scroll/loaded data.
@MainActor
@Observable
final class LibraryBrowseModel {
    /// Per-list load state (drives spinner / empty / error / first-run affordances).
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case firstRun // no scan-folder roots registered yet
        case failed(String)
    }

    /// Navigation state — MUST survive tab teardown, so it lives here (design §2).
    var selectedCategory: LibraryCategory? = .albums {
        didSet {
            // A category switch resets the detail drill-down; otherwise a pushed album/artist
            // detail stays visible UNDER the newly-selected category's root (review blocker).
            // This assigns `path`, NOT `selectedCategory`, so it can't self-recurse a @Observable
            // didSet.
            if selectedCategory != oldValue { path.removeAll() }
        }
    }

    var path: [LibraryRoute] = []

    // Albums (S9.4). Songs/artists/genres/years arrays land in S9.5/S9.6.
    private(set) var albums: [AlbumFacet] = []
    var albumSort: FacetSort = .title // S9.5 adds a "Recently Added" album sort (needs a DAO read)
    private(set) var albumsState: LoadState = .idle

    /// Library folders (the "Music Folders" management surface — S9 IA change).
    private(set) var roots: [LibraryFolder] = []

    private let audio: AudioViewModel
    private var artwork: ArtworkThumbnailStore?
    /// The `audio.libraryRevision` last loaded, so `reloadIfScanChanged` reloads exactly once
    /// per library-content change (scan / metadata pass / reconcile).
    private var lastLoadedRevision = 0
    /// Monotonic load token — only the newest in-flight `loadAlbums` may publish, guarding the
    /// sort-change vs scan-reload last-completer race (review S3).
    private var loadEpoch = 0
    /// Same guard for the roots list (its reloads race adds/removes + libraryRevision).
    private var loadRootsEpoch = 0

    init(audio: AudioViewModel) {
        self.audio = audio
    }

    // MARK: - Store access

    /// The store once `AudioViewModel` has finished building it (async at launch); nil early.
    private var store: LibraryStore? {
        audio.store
    }

    /// Whether the async-built store is ready. Drives the grid's initial load so a Library-tab
    /// visit BEFORE the store finishes constructing isn't stuck on a spinner (review S2).
    var isStoreReady: Bool {
        audio.store != nil
    }

    /// Whether a scan / metadata pass / live reconcile is currently populating the library — lets
    /// the browse UI show a truthful "scanning" affordance instead of a permanent one for a
    /// genuinely empty result (review S1). Reactive: reads published `AudioViewModel` state.
    var isPopulating: Bool {
        audio.scanProgress != nil || audio.metadataProgress != nil || audio.isReconciling
    }

    /// A short, phase-aware status line for the sidebar scan strip, or nil when idle. Coarse by
    /// design (one line per phase, not per tick).
    var scanStatusText: String? {
        if let scan = audio.scanProgress { return "Scanning… \(scan.filesSeenSoFar) files" }
        if audio.metadataProgress != nil { return "Reading tags…" }
        if audio.isReconciling { return "Updating library…" }
        return nil
    }

    /// The root currently being scanned (for a per-row "scanning…" hint), or nil.
    var scanningRootID: Int64? {
        audio.scanProgress?.folderID
    }

    private func ensureArtwork() {
        if artwork == nil, let store { artwork = ArtworkThumbnailStore(store: store) }
    }

    // MARK: - Folder management (the "Music Folders" surface — S9 IA change)

    /// Refresh the registered-roots list (drives the Music Folders popover). Epoch-guarded like
    /// `loadAlbums` so a slow read can't overwrite a newer one (add/remove + libraryRevision +
    /// scan-progress all trigger reloads concurrently — review S3/#2).
    func loadRoots() async {
        loadRootsEpoch &+= 1
        let epoch = loadRootsEpoch
        let loaded = (try? await store?.roots()) ?? []
        guard epoch == loadRootsEpoch else { return }
        roots = loaded
    }

    /// Add a music folder — SCAN ONLY (never touches the queue, design §2/§5). The single
    /// add path shared by the sidebar footer, the Music Folders popover, and the first-run CTA,
    /// so scan-only + nested-root rejection can't drift between entry points.
    func addFolder(_ url: URL) {
        audio.scanFolderIntoLibrary(url)
    }

    /// Remove a registered root and refresh the list. Deletes the folder's library rows (files on
    /// disk + the queue are untouched — see `AudioViewModel.removeLibraryFolder`).
    func removeFolder(id: Int64) async {
        await audio.removeLibraryFolder(id: id)
        await loadRoots()
    }

    // MARK: - Album loading

    /// Load the album grid. Sets `firstRun` when no roots are registered, `empty` when roots
    /// exist but no albums yet (mid-scan / empty folders), `failed` on error.
    func loadAlbums() async {
        guard let store else {
            albumsState = .loading // store still building; the grid reloads on `isStoreReady`
            return
        }
        ensureArtwork()
        loadEpoch &+= 1
        let epoch = loadEpoch
        if albums.isEmpty { albumsState = .loading } // keep showing cached data while refreshing
        do {
            let loaded = try await store.albums(sortedBy: albumSort)
            guard epoch == loadEpoch else { return } // a newer load superseded this one
            albums = loaded
            if loaded.isEmpty {
                let hasRoots = try await !store.roots().isEmpty
                guard epoch == loadEpoch else { return }
                albumsState = hasRoots ? .empty : .firstRun
            } else {
                albumsState = .loaded
            }
        } catch {
            guard epoch == loadEpoch else { return }
            albumsState = .failed(error.localizedDescription)
        }
    }

    /// Reload the visible facets when a scan / metadata pass / reconcile completes (albums + art
    /// fill in live). Coalesced to `audio.libraryRevision` — one reload per pass, NOT per metadata
    /// tick (design §7; review B1 — the revision bumps when metadata builds the album rows, not
    /// at the earlier `lastScanResult` set, so a fresh scan's albums actually appear).
    func reloadIfScanChanged() async {
        guard audio.libraryRevision != lastLoadedRevision else { return }
        lastLoadedRevision = audio.libraryRevision
        await loadAlbums()
    }

    // MARK: - Detail reads (album)

    func album(id: Int64) async -> AlbumFacet? {
        try? await store?.album(id: id)
    }

    func tracks(inAlbum albumID: Int64) async -> [LibraryTrackDisplay] {
        (try? await store?.tracksDisplay(inAlbum: albumID)) ?? []
    }

    // MARK: - Artwork (delegates to the lazy ArtworkThumbnailStore; nil → placeholder)

    func warmArtwork(_ keys: [String]) async {
        ensureArtwork()
        await artwork?.warm(keys: keys)
    }

    func cachedArtwork(forKey key: String) -> NSImage? {
        artwork?.cachedImage(forKey: key)
    }

    func artworkImage(forKey key: String, maxPixel: Int) async -> NSImage? {
        ensureArtwork()
        return await artwork?.image(forKey: key, maxPixel: maxPixel)
    }

    // MARK: - Play actions (delegate to AudioViewModel's queue verbs)

    /// Play the album now, starting from `startAt` within its (disc/track-ordered) tracks.
    func playAlbum(_ albumID: Int64, startAt index: Int = 0) async {
        let files = await tracks(inAlbum: albumID).map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.playNow(files, startAt: index)
    }

    func playAlbumNext(_ albumID: Int64) async {
        let files = await tracks(inAlbum: albumID).map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.playNext(files)
    }

    func appendAlbum(_ albumID: Int64) async {
        let files = await tracks(inAlbum: albumID).map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.appendToQueue(files)
    }

    /// Play a specific set of already-loaded display tracks now (album-detail row tap).
    func play(_ tracks: [LibraryTrackDisplay], startAt index: Int) {
        let files = tracks.map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.playNow(files, startAt: index)
    }

    func playNext(_ tracks: [LibraryTrackDisplay]) {
        audio.playNext(tracks.map(AudioFile.init))
    }

    func append(_ tracks: [LibraryTrackDisplay]) {
        audio.appendToQueue(tracks.map(AudioFile.init))
    }
}
