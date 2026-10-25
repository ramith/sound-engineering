import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - The library search behind ⌘F (R1.1-B, US-R1F-14)

/// ⌘F's search over the whole library — songs, albums, artists, genres and playlists — on the Library's
/// Search page. One search rule (`SearchRule`; founder 2026-10-25): each section keeps exactly what that
/// tab's Filter keeps for the query (`LibrarySearch`), and where a tab keeps its own sort, ⌘F ranks.
/// Owned by `LibraryBrowseModel` (`search`), so the text and the results survive a tab switch.
///
/// Typing runs the search through the page's debounce (~120 ms, as the Songs filter): below the
/// two-character gate (`SearchQueryGate`) nothing is searched or shown; each edit invalidates any search
/// in flight at once and the newest search wins (`SearchEpoch`); a failed read keeps the last results.
/// The store reads run off the main actor, and so does the ranking.
@MainActor
@Observable
final class LibrarySearchModel {
    /// Where the search stands — what the page shows under its field.
    enum State: Equatable {
        /// Below the two-character gate: nothing searched.
        case idle
        /// A search for the current text is running (the last results stay on screen).
        case searching
        /// The results are the current text's.
        case done
    }

    /// The search field's text. An edit invalidates any search in flight; below the gate it clears the
    /// results at once.
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            epoch.invalidate()
            if !SearchQueryGate.shouldQuery(text) {
                results = .empty
                state = .idle
            }
        }
    }

    private(set) var results = LibrarySearchResults.empty
    private(set) var state = State.idle

    /// ⌘F's focus intent: set by `LibraryBrowseModel.beginSearch`, taken by the Search page when it shows
    /// (`takeFocusRequest`) — it focuses its field, which keeps its text.
    private(set) var focusRequested = false

    @ObservationIgnored private var epoch = SearchEpoch()
    @ObservationIgnored private let library: LibraryModel

    init(library: LibraryModel) {
        self.library = library
    }

    /// Ask the Search page to focus its field.
    func requestFocus() {
        focusRequested = true
    }

    /// Take the focus intent: true once per request.
    func takeFocusRequest() -> Bool {
        guard focusRequested else { return false }
        focusRequested = false
        return true
    }

    /// Search for the current text: the store's lists read and ranked off the main actor, published only
    /// when no edit and no newer search came since.
    func run() async {
        let read = epoch.beginRead()
        let query = text
        guard SearchQueryGate.shouldQuery(query) else {
            results = .empty
            state = .idle
            return
        }
        guard let store = library.store else { return }
        state = .searching
        let found = try? await Task.detached(priority: .userInitiated) {
            try await Self.search(query, in: store)
        }.value
        guard epoch.isCurrent(read) else { return }
        if let found {
            results = found
        }
        state = .done
    }

    /// Search again when the library changed under a showing search (a scan added or removed songs).
    func rerunIfSearching() async {
        guard SearchQueryGate.shouldQuery(text) else { return }
        await run()
    }

    /// The results for `query`: the songs the index finds, and every list as its tab lists it.
    private nonisolated static func search(_ query: String, in store: LibraryStore) async throws
        -> LibrarySearchResults {
        async let ids = store.searchMatchingIDs(query)
        async let albums = store.albums(sortedBy: .title)
        async let artists = store.artists()
        async let genres = store.genres()
        async let playlists = store.playlists()
        let songs = try await Array(store.tracksDisplay(ids: Array(ids)).values)
        let lists = try await LibrarySearch.Lists(
            songs: songs, albums: albums, artists: artists, genres: genres,
            playlists: PlaylistBrowseVisibility.userVisible(playlists)
        )
        return LibrarySearch.results(for: query, in: lists)
    }
}

// MARK: - ⌘F and the Search page's actions

@MainActor
extension LibraryBrowseModel {
    /// How many rows ⌘F shows of a section before "Show All".
    static func searchRowLimit(_ section: LibrarySearchSection) -> Int {
        section == .songs ? 8 : 5
    }

    /// ⌘F, from any tab: the Library's Search page, its field focused — keeping what it holds.
    func beginSearch() {
        audio.selectedTab = .library
        if selectedCategory != .search || !path.isEmpty {
            selectCategory(.search)
        }
        search.requestFocus()
    }

    /// A result row's action: a song plays now, after the song playing (the Songs list's double-click);
    /// an album, artist or genre opens its page over the search (back returns to it); a playlist opens.
    func activate(_ item: LibrarySearchItem) {
        switch item {
        case let .song(id):
            if let track = search.results.songs.first(where: { $0.id == id }) {
                playTrackNextNow(track)
            }
        case let .album(id): path.append(.album(id))
        case let .artist(id): path.append(.artist(id))
        case let .genre(id): path.append(.genre(id))
        case let .playlist(id): selectPlaylist(id)
        }
    }

    /// "Show All" in a section: that tab, its Filter holding the query — the same items, in the tab's own
    /// sort. Playlists have no tab: their section lists them all.
    func showAll(_ section: LibrarySearchSection) {
        let query = search.text
        switch section {
        case .songs:
            selectCategory(.songs)
            searchQuery = query
        case .albums, .artists, .genres:
            selectCategory(section == .albums ? .albums : section == .artists ? .artists : .genres)
            browseFilter = query
        case .playlists:
            break
        }
    }
}

#if DEBUG
    extension LibrarySearchModel {
        /// Picture-sheet renderer only (`Debug/SheetFixture+Search.swift`): show `results` for `text`,
        /// without a store.
        func seedRenderFixture(text: String, results: LibrarySearchResults) {
            self.text = text
            self.results = results
            state = .done
        }
    }
#endif
