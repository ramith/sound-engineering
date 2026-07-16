import AppKit
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import SwiftUI

// MARK: - LibraryBrowseModel (S9.4 — the browse view-model)

/// Owns all Library-tab browse state and is the seam between the browse UI (reads + selection) and
/// the two model peers it composes: `LibraryModel` (the store + scan/reconcile state it READS) and
/// `AudioViewModel` (the playback + queue verbs it PLAYS through). `@Observable` + `@MainActor`, a
/// peer of `EQViewModel`. ★ Owned as `@State` in the `App` and injected via `.environment` — NOT
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

    /// Navigation state — MUST survive tab teardown, so it lives here (design §2). Default flips
    /// `.albums → .songs` (S9.5 D8 / §10.0): Songs is the landing so the app never opens onto the
    /// old placeholder, and loose album-less singles are reachable from the first frame.
    var selectedCategory: LibraryCategory? = .songs {
        didSet {
            // A category switch resets the detail drill-down; otherwise a pushed album/artist
            // detail stays visible UNDER the newly-selected category's root (review blocker).
            // This assigns `path`, NOT `selectedCategory`, so it can't self-recurse a @Observable
            // didSet.
            if selectedCategory != oldValue { path.removeAll() }
        }
    }

    var path: [LibraryRoute] = []

    // Sidebar selection (S10.3) lives in `LibraryBrowseModel+Sidebar` (a same-type extension, split
    // for file length): `sidebarSelection` + `selectCategory`/`selectPlaylist`.

    // Albums (S9.4).
    private(set) var albums: [AlbumFacet] = []
    var albumSort: FacetSort = .title // S9.5 adds a "Recently Added" album sort (needs a DAO read)
    private(set) var albumsState: LoadState = .idle

    // Artists / Genres / Years (S9.6). Each mirrors the albums list pattern (array + LoadState +
    // epoch). Declared `internal` (not `private(set)`) because their loaders live in the same-type
    // `LibraryBrowseModel+Facets` extension — split to a separate file for file length — which a
    // `private` setter can't reach; in practice only the model writes them.
    var artists: [ArtistFacet] = []
    var artistsState: LoadState = .idle
    var genres: [GenreFacet] = []
    var genresState: LoadState = .idle

    /// Songs (S9.5 D8). OD-1 full-load: the ENTIRE sorted set is held in memory (≤20k compact
    /// structs ≈ a few MB, no keyset cursor), so the loaded array IS the play order — play-from-row
    /// indexes straight into it with no separate read. `songSort` drives the DAO-side order (header
    /// sort UI is slice 3); the composite default groups by artist → album → disc → track → id.
    private(set) var songs: [LibraryTrackDisplay] = [] {
        didSet { refreshVisible() } // one recompute per full-load (design §5/L1)
    }

    var songSort: TrackSort = .artistAlbumTrack
    /// The Songs `Table`'s active-column comparator — the SINGLE SOURCE OF TRUTH for the sort
    /// triangle (review #1). It lives HERE (not `@State` in the table subtree) so it survives the
    /// tab-`switch` teardown alongside `songSort`; a subtree `@State` would re-seed to the anchor
    /// on every return and desync the triangle from the persisted `songSort`. Seeded to the Artist
    /// anchor while `songSort` stays the composite grouped default (`.artistAlbumTrack`); `onChange`
    /// does NOT fire on this seed, so it never clobbers the composite (design §3.1).
    var sortOrder: [KeyPathComparator<LibraryTrackDisplay>] = [
        KeyPathComparator(\.artistName, order: .forward),
    ]
    private(set) var songsState: LoadState = .idle

    /// Recently-Played (frecency) rows (S10.6) — the DAO returns them already frecency-ordered
    /// (recency-weighted play frequency). Loaded when the Recently-Played tab appears and refreshed
    /// when a play crosses the ≥60% threshold (`AudioViewModel.playCountRevision`). Declared
    /// `internal` (not `private(set)`) because the loader lives in a same-type extension
    /// (`LibraryBrowseModel+History`).
    var history: [LibraryTrackDisplay] = []
    var historyState: LoadState = .idle
    var historyLoadEpoch = 0

    // Songs filter (S9.5 chunk 2b — "filter-preserves-sort", design §3.3/§5). The filter NARROWS
    // the already-`songSort`-ordered `songs` in place (A2): it never touches `songSort`/`sortOrder`,
    // so the sort triangle is preserved and headers keep re-sorting the filtered subset.

    /// The live filter text, bound to the header field via `@Bindable` and observed by the
    /// SongsView-level debounce `.task(id:)`. Editing **synchronously** invalidates any in-flight
    /// read (bumps the epoch) and, on dropping below the 2-char gate, clears the filter at once — so
    /// a backspace/clear can't leave a stale filter flashing through the 120 ms debounce (review
    /// LOW-1). A ≥2-char edit keeps the last-good set until the new read lands (no flash to empty).
    var searchQuery: String = "" {
        didSet {
            searchEpoch.invalidate() // invalidate any dispatched read immediately, not after the debounce
            if !SearchQueryGate.shouldQuery(searchQuery) {
                matchedIDs = nil // instant restore-to-full; don't wait for the debounced runFilter
            }
        }
    }

    /// The FTS-matched `tracks.id`s, or the filter mode. **`nil` = NOT filtering** →
    /// `visibleSongs` short-circuits to `songs` (identity, no copy); **`[]` = filtering with zero
    /// matches** → drives the zero-results state. A concrete set narrows `songs` to that membership.
    private(set) var matchedIDs: Set<Int64>? {
        didSet { refreshVisible() } // one recompute per filter publish (design §5/L1)
    }

    /// The single source the Songs table/count/row-resolution bind to — the current sort narrowed
    /// by the active filter. **Cached, NOT a per-`body` computed (L1):** selection lives as `@State`
    /// in the table subtree, so every arrow-key move re-evals `body`; an O(n) refilter per keystroke
    /// would threaten OD-1's hard <100 ms selection gate. Recomputed by `refreshVisible()` ONLY when
    /// `songs` or `matchedIDs` changes (their `didSet`s).
    private(set) var visibleSongs: [LibraryTrackDisplay] = []

    /// Monotonic newest-wins guard (`LibraryBrowseKit.SearchEpoch`) for the actor round-trip in
    /// `runFilter`. `invalidate()` is called **synchronously on every `searchQuery` edit** (its
    /// `didSet`), not inside the debounced `runFilter` — so an already-dispatched `searchMatchingIDs`
    /// from a prior query is invalidated the instant the user edits and can't publish a stale result
    /// after the field has moved on (review LOW-1). `.task(id:)` cancellation alone can't interrupt an
    /// in-flight actor call, hence the epoch.
    private var searchEpoch = SearchEpoch()

    /// Queue-add toast (S9.5 §10.4). State lives HERE (Library is the only queue-adder — arch #4, not
    /// a global service); the shell-hosted `QueueToast` view renders + announces off `queueToast`.
    /// The current toast, or nil. No `didSet` (so no @Observable self-assign trap); the `token` is a
    /// monotonic key the VIEW uses as its announce + animation trigger, so a coalesced replace with an
    /// IDENTICAL string still re-announces/re-renders (review swiftui #1/#5).
    struct QueueToastState: Equatable {
        let message: String
        let token: Int
    }

    private(set) var queueToast: QueueToastState?
    private var queueToastToken = 0
    /// Single cancellable dismiss task (cancel-and-respawn) — NOT one task per raise. The post-sleep
    /// `!Task.isCancelled` guard stops a superseded task from clearing a newer toast (review swiftui #3).
    private var queueToastDismissTask: Task<Void, Never>?

    /// Library folders (the "Music Folders" management surface — S9 IA change).
    private(set) var roots: [LibraryFolder] = []

    /// `audio` / `library` / `store` / `showQueueToast` are `internal` (not `private`) so the
    /// same-type `LibraryBrowseModel+Facets` extension (a separate file, for file length) can reach
    /// them — an extension of this type IS this type, and the app is a single module.
    let audio: AudioViewModel
    /// The library subsystem this browse layer READS (store, scan/reconcile progress, revision).
    /// A peer of `audio`, kept as a separate dependency so playback verbs and library reads route
    /// to the right owner (S3 F5 — the God-object split).
    let library: LibraryModel
    private var artwork: ArtworkThumbnailStore?
    /// The `library.libraryRevision` last loaded, so `reloadIfScanChanged` reloads exactly once
    /// per library-content change (scan / metadata pass / reconcile).
    private var lastLoadedRevision = 0
    /// Monotonic load token — only the newest in-flight `loadAlbums` may publish, guarding the
    /// sort-change vs scan-reload last-completer race (review S3).
    private var loadEpoch = 0
    /// Same monotonic-token guard as `loadEpoch`, for `loadSongs` — its full-load races the
    /// scan-reload and (slice 3) a sort change; only the newest completer may publish.
    private var songsLoadEpoch = 0
    /// Same guard for the roots list (its reloads race adds/removes + libraryRevision).
    private var loadRootsEpoch = 0
    /// Newest-wins tokens for the facet-list loaders (mutated by `LibraryBrowseModel+Facets`).
    var artistsLoadEpoch = 0
    var genresLoadEpoch = 0

    init(audio: AudioViewModel, library: LibraryModel) {
        self.audio = audio
        self.library = library
    }

    // MARK: - Store access

    /// The store once `LibraryModel` has finished building it (async at launch); nil early.
    /// `internal` — the +Facets loaders read it (see the `audio`/`library` note above).
    var store: LibraryStore? {
        library.store
    }

    /// Whether the async-built store is ready. Drives the grid's initial load so a Library-tab
    /// visit BEFORE the store finishes constructing isn't stuck on a spinner (review S2).
    var isStoreReady: Bool {
        library.store != nil
    }

    /// Whether a scan / metadata pass / live reconcile is currently populating the library — lets
    /// the browse UI show a truthful "scanning" affordance instead of a permanent one for a
    /// genuinely empty result (review S1). Reactive: reads published `LibraryModel` state.
    var isPopulating: Bool {
        library.scanProgress != nil || library.metadataProgress != nil || library.isReconciling
    }

    /// A short, phase-aware status line for the sidebar scan strip, or nil when idle. Coarse by
    /// design (one line per phase, not per tick).
    var scanStatusText: String? {
        if let scan = library.scanProgress { return "Scanning… \(scan.filesSeenSoFar) files" }
        if library.metadataProgress != nil { return "Reading tags…" }
        if library.isReconciling { return "Updating library…" }
        return nil
    }

    /// The root currently being scanned (for a per-row "scanning…" hint), or nil.
    var scanningRootID: Int64? {
        library.scanProgress?.folderID
    }

    /// Lazily build the thumbnail store once the async `store` exists (used by the Artwork
    /// extension's passthrough + `loadAlbums`). Private; reached from the same-file extension.
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
        library.scanFolderIntoLibrary(url)
    }

    /// Remove a registered root and refresh the list. Deletes the folder's library rows (files on
    /// disk + the queue are untouched — see `LibraryModel.removeLibraryFolder`).
    func removeFolder(id: Int64) async {
        await library.removeLibraryFolder(id: id)
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

    // MARK: - Song loading (S9.5 — OD-1 full-load)

    /// Full-load the Songs list: the ENTIRE sorted set into memory (`allTracksDisplay(limit: nil)`,
    /// no cursor — OD-1). Mirrors `loadAlbums`'s epoch / `isStoreReady` / firstRun-vs-empty
    /// discipline; `songSort` drives the DAO-side order, so `songs` is already the play order.
    func loadSongs() async {
        guard let store else {
            songsState = .loading // store still building; the list reloads on `isStoreReady`
            return
        }
        songsLoadEpoch &+= 1
        let epoch = songsLoadEpoch
        if songs.isEmpty { songsState = .loading } // keep showing cached rows while refreshing
        do {
            let loaded = try await store.allTracksDisplay(sortedBy: songSort, limit: nil)
            guard epoch == songsLoadEpoch else { return } // a newer load superseded this one
            songs = loaded
            if loaded.isEmpty {
                let hasRoots = try await !store.roots().isEmpty
                guard epoch == songsLoadEpoch else { return }
                songsState = hasRoots ? .empty : .firstRun
            } else {
                songsState = .loaded
            }
        } catch {
            guard epoch == songsLoadEpoch else { return }
            songsState = .failed(error.localizedDescription)
        }
    }

    /// Map the Songs table's active-column comparator → a `TrackSort` (via
    /// `LibraryBrowseKit.SongSortMapping`, unit-tested) and re-read DAO-side. The triangle rides
    /// `sortOrder` (single source of truth, §3.1); the mapping translates the PRIMARY comparator's
    /// keypath + direction into the matching asc/desc `TrackSort` (unrecognized / empty → composite
    /// default), sets `songSort`, and re-loads. Sorting stays index-driven in SQL (`allTracksDisplay`),
    /// never a client-side sort of the full ≤20k set.
    func applySortOrder(_ comparators: [KeyPathComparator<LibraryTrackDisplay>]) {
        songSort = SongSortMapping.trackSort(for: comparators)
        Task { await self.loadSongs() }
    }

    // MARK: - Song filtering (S9.5 chunk 2b — filter-preserves-sort, A2)

    /// Recompute the cached `visibleSongs` from `songs` + `matchedIDs`. The ONLY writer of
    /// `visibleSongs`; invoked from the `songs`/`matchedIDs` `didSet`s so every input change
    /// refreshes exactly once (design §5/L1). When NOT filtering (`matchedIDs == nil`) it assigns
    /// `songs` by identity — no `filter`, no copy — so the common unfiltered path stays free. `songs`
    /// is already in `songSort` order, so the in-place membership filter preserves that order for
    /// free (A2): it can only ever hide a row, never reorder or fabricate one.
    private func refreshVisible() {
        if let matchedIDs {
            visibleSongs = songs.filter { matchedIDs.contains($0.id) }
        } else {
            visibleSongs = songs
        }
    }

    /// Run the active filter: gate on ≥2 (trimmed) chars, hit the IDs-only membership read off-main,
    /// and publish newest-wins. `nil` = not filtering (restore full list); `[]` (junk /
    /// tokenizable-no-match) = zero results. A stale epoch OR a store error keeps the last-good set
    /// (never a silent restore-to-full). The epoch is bumped in `searchQuery`'s `didSet`, so we only
    /// CAPTURE it here; any newer edit that lands during the read drops this publish. Debounced +
    /// cancelled by the SongsView `.task(id:)` (§7); also called directly on a filtered background
    /// reload (§11 #4), where no edit occurred and the captured epoch simply stays current.
    func runFilter() async {
        let captured = searchEpoch.value
        guard SearchQueryGate.shouldQuery(searchQuery) else {
            matchedIDs = nil
            return
        }
        guard let ids = try? await store?.searchMatchingIDs(searchQuery), searchEpoch.isCurrent(captured)
        else { return } // stale epoch OR store error/not-ready → keep last-good, no publish
        matchedIDs = ids // [] on junk/no-match (never nil here) → drives zero-results
    }

    /// The Songs summary line: unfiltered "N songs · total duration"; filtered "N results" (duration
    /// dropped; `0` → "0 results"). Driven off `visibleSongs`/`matchedIDs` (design §3.3/§6).
    var songsCountLine: String {
        let count = visibleSongs.count
        if matchedIDs != nil {
            let noun = count == 1 ? "result" : "results"
            return "\(count.formatted(.number)) \(noun)"
        }
        let noun = count == 1 ? "song" : "songs"
        let total = humaneTotalDuration(visibleSongs.reduce(0.0) { $0 + $1.durationSeconds })
        return "\(count.formatted(.number)) \(noun) · \(total)"
    }

    /// Reload the visible facets when a scan / metadata pass / reconcile completes (albums + songs
    /// + art fill in live). Coalesced to `library.libraryRevision` — one reload per pass, NOT per
    /// metadata tick (design §7; review B1 — the revision bumps when metadata builds the rows, not
    /// at the earlier `lastScanResult` set, so a fresh scan's content actually appears). Both lists
    /// refresh (each epoch-guarded independently); the visible one shows cached rows same-frame.
    func reloadIfScanChanged() async {
        guard library.libraryRevision != lastLoadedRevision else { return }
        lastLoadedRevision = library.libraryRevision
        await loadAlbums()
        await loadSongs()
        // The facet lists refresh on the same revision bump (each epoch-guarded), else the
        // Artists/Genres roots + their counts go stale mid-scan (swiftui review #5).
        await loadArtists()
        await loadGenres()
        // Re-run the active filter after the reload (design §11 decision #4 / L2): a live scan may
        // have added tracks that match the current query, and the reload replaced `songs` while
        // leaving the stale `matchedIDs`. Re-querying surfaces the new matches; `matchedIDs`'s
        // `didSet` refreshes `visibleSongs`. Skipped when not filtering (`matchedIDs == nil`).
        if matchedIDs != nil { await runFilter() }
    }

    // MARK: - Detail reads (album)

    func album(id: Int64) async -> AlbumFacet? {
        try? await store?.album(id: id)
    }

    func tracks(inAlbum albumID: Int64) async -> [LibraryTrackDisplay] {
        (try? await store?.tracksDisplay(inAlbum: albumID)) ?? []
    }

    // Play actions (playAlbum / play / playNext / append / playTrackNextNow) live in
    // `LibraryBrowseModel+Play` (a same-type extension, split for file length).

    // MARK: - Queue toast (S9.5 §10.4)

    /// Raise the visibility-gated queue-add toast for a completed add. Silent for Play Now, on the
    /// Now Playing tab, or whenever `QueueToastDecision` suppresses it (see `raiseToast` for the
    /// coalesce/auto-dismiss mechanics).
    func showQueueToast(_ verb: QueueVerb, added: Int) {
        guard let message = QueueToastDecision.message(
            verb: verb, addedCount: added, isNowPlayingTab: audio.selectedTab == .nowPlaying
        ) else { return }
        raiseToast(message)
    }

    /// Raise a plain-message toast on the shell surface (S10.3 playlist-add "Added N songs to …").
    func showToast(_ message: String) {
        raiseToast(message)
    }

    /// Shared raise+coalesce+auto-dismiss for the shell toast (queue add / playlist add): replaces
    /// the text + resets the ~2 s timer (single cancellable task; post-sleep guard prevents a
    /// superseded task clearing the newer toast); the token re-announces even an identical string.
    private func raiseToast(_ message: String) {
        queueToastToken &+= 1
        queueToast = QueueToastState(message: message, token: queueToastToken)
        queueToastDismissTask?.cancel()
        queueToastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.queueToast = nil
        }
    }

    /// Clear the toast immediately — tap-through / entering Now Playing — so the render gate can't let
    /// a stale toast reappear on return to a gated tab within the window (review swiftui #2).
    func dismissQueueToast() {
        queueToastDismissTask?.cancel()
        queueToast = nil
    }
}

// MARK: - Artwork (delegates to the lazy ArtworkThumbnailStore; nil → placeholder)

//
// A same-file extension: pure passthrough to `ArtworkThumbnailStore`, grouped as its own concern
// (and kept off the class-body length). Calls the class's private `ensureArtwork` (a same-file
// extension reaches it); the thumbnail store is built lazily once the async `store` exists.

@MainActor
extension LibraryBrowseModel {
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
}
