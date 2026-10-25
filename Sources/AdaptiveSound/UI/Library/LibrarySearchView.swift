import LibraryBrowseKit
import SwiftUI

// MARK: - The Library's Search page (R1.1-B, US-R1F-14 — ⌘F)

/// The Search page: the Library card's header with the search field (⌘F focuses it from any tab — the
/// app's Find command), then the results in sections — Songs, Albums, Artists, Genres, Playlists — each
/// ranked by one relevance rule (`SearchRelevance`) and each keeping exactly what that tab's Filter keeps
/// for the query (`LibrarySearch`; one word-start rule — founder, 2026-10-25). A section shows its first
/// few rows and "Show All" opens its tab with the query in the tab's Filter: the same items, in the tab's
/// own sort.
///
/// Keyboard: the card's one focus value (`CardFocus`, K1) — the field is `.filter`, the results
/// `.content`, so Esc in the field clears it and lands on the results; ↑/↓ walk every shown row; Return
/// plays a song or opens anything else. A single click on a song selects it and a double-click plays it,
/// as on Songs; a click on an album, artist, genre or playlist opens it.
struct LibrarySearchView: View {
    @Environment(LibraryBrowseModel.self) private var model
    @FocusState private var focus: CardFocus?
    /// The results' keyboard cursor (and a song's selection).
    @State private var cursor: LibrarySearchItem?
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    /// The clock the search's debounce sleeps on.
    var clock: any Clock<Duration> = ContinuousClock()

    var body: some View {
        @Bindable var search = model.search
        VStack(spacing: 0) {
            LibraryCardHeader(title: "Search", count: countLine, filter: $search.text, filterPrompt: "Search Library",
                              focus: $focus, focusShortcut: nil)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The debounced search (as the Songs filter, ~120 ms): a keystroke changes the task id, which
        // cancels the sleeping task; the model's epoch drops a search a newer one superseded.
        .task(id: search.text) {
            try? await clock.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await search.run()
        }
        // ⌘F's focus intent — on appearing (⌘F from another tab) and while showing.
        .task(id: search.focusRequested) {
            if search.takeFocusRequest() {
                focus = .filter
            }
        }
    }

    /// "Songs, albums, artists, genres and playlists" until a search runs; then "N results".
    private var countLine: String {
        guard model.search.state != .idle else { return "Songs, albums, artists, genres and playlists" }
        let total = LibrarySearchSection.allCases.reduce(0) { $0 + model.search.results.count(of: $1) }
        return FacetCountLabel.count(total, noun: "result", filtered: true)
    }

    @ViewBuilder private var content: some View {
        let search = model.search
        if search.state == .idle {
            ContentUnavailableView {
                Label("Search Your Library", systemImage: "magnifyingglass")
            } description: {
                Text("Type two letters or more. A song, album, artist, genre or playlist is found when a word "
                    + "in it starts with what you type.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focused($focus, equals: .content)
        } else if search.results.isEmpty, search.state == .done {
            LibraryNoResultsView(items: "songs, albums, artists, genres or playlists", query: search.text)
                .focusable()
                .focused($focus, equals: .content)
        } else {
            results
        }
    }

    // MARK: Results

    private var shown: [LibrarySearchItem] {
        model.search.results.shownItems(limit: LibraryBrowseModel.searchRowLimit)
    }

    private var results: some View {
        let rows = shown
        let ring = showsKeyboardFocus && focus == .content ? keyboardCursor(rows)?.id : nil
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(LibrarySearchSection.allCases, id: \.self) { section in
                        sectionView(section, ring: ring)
                    }
                }
                .padding(.vertical, DesignSystem.LayoutMetrics.cardRowAreaInsetV)
                .padding(.horizontal, DesignSystem.LayoutMetrics.cardRowAreaInsetH)
            }
            .focusable()
            .focused($focus, equals: .content)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard !press.isShortcut else { return .ignored }
                return move(by: press.key == .upArrow ? -1 : 1, in: rows, proxy: proxy)
            }
            .onKeyPress(keys: [.return]) { press in
                guard !press.isShortcut,
                      let target = keyboardCursor(rows)?.activationTarget(ringVisible: showsKeyboardFocus)
                else { return .ignored }
                model.activate(target)
                return .handled
            }
        }
    }

    /// ↑/↓: move the cursor `delta` rows and keep it on screen; `.ignored` past the first or last row.
    private func move(by delta: Int, in rows: [LibrarySearchItem], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let next = keyboardCursor(rows)?.step(by: delta, in: rows) else { return .ignored }
        cursor = next
        proxy.scrollTo(next)
        return .handled
    }

    private func keyboardCursor(_ rows: [LibrarySearchItem]) -> ListKeyboardCursor<LibrarySearchItem>? {
        ListKeyboardCursor.resolve(rows: rows, anchor: cursor)
    }

    @ViewBuilder
    private func sectionView(_ section: LibrarySearchSection, ring: LibrarySearchItem?) -> some View {
        let results = model.search.results
        let count = results.count(of: section)
        if count > 0 {
            LibrarySearchSectionHeader(section: section, count: count,
                                       showsAll: section != .playlists
                                           && count > LibraryBrowseModel.searchRowLimit(section)) {
                model.showAll(section)
            }
            ForEach(results.items(of: section, limit: LibraryBrowseModel.searchRowLimit(section)), id: \.self) { item in
                LibrarySearchRow(item: item, results: results, isSelected: cursor == item,
                                 isKeyboardCursor: ring == item,
                                 select: { cursor = item; focus = .content },
                                 activate: { model.activate(item) })
                    .id(item)
            }
        }
    }
}
