import SwiftUI

// MARK: - Songs list (S9.5)

/// The Library's default landing: the full-library song list over the in-memory full-load set
/// (`LibraryBrowseModel.songs`, OD-1), on the Library's one glass card (mounted by
/// `LibraryTabView`, S10.8 D1). Header + customizable-column custom list (`SongsHeader` +
/// `SongsListView`, S10.8 PR-D — replaced the SwiftUI `Table`), the composite default order,
/// double-click / Return play-from-row, and the "N songs · total" count.
///
/// The load states are the Library card roots' shared machine (`LibraryLoadStateView`): a
/// `.task(id:)` keyed on store-readiness kicks the full-load, and `.onChange(of: libraryRevision)`
/// (in `LibraryTabView`) reloads once per pass. Header + list are shown only when there ARE rows.
struct SongsView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        LibraryLoadStateView(state: model.songsState, isEmpty: model.songs.isEmpty) {
            // `.loaded` but empty means every track was removed — a genuine empty library.
            LibraryEmptyStateView(kind: .emptyLibrary)
        } content: {
            songsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keyed on store-readiness so a Library visit BEFORE the async store finishes building
        // reloads once it's ready (mirrors the browse grids / review S2) — not a stuck spinner.
        .task(id: model.isStoreReady) { await model.loadSongs() }
        // Debounced incremental filter (§7). A new keystroke changes the task id → the sleeping
        // task is cancelled → newest-wins on the debounce; the model's epoch guard covers the
        // actor round-trip a cancel can't interrupt. Hosted HERE (the stable SongsView body, not
        // the re-rendering SongsHeader) so it isn't torn down by header updates.
        .task(id: model.searchQuery) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await model.runFilter()
        }
    }

    /// Header + list — shown only when there is content (design §10.3). When a filter is active but
    /// matches nothing (`matchedIDs == []`), the list is replaced by "no results" while the header
    /// (field + "0 results") stays — DISTINCT from the empty-library state, which is reached only
    /// when there's genuinely no library content (§3.3/§10.3).
    private var songsList: some View {
        VStack(spacing: 0) {
            SongsHeader()
            if model.matchedIDs?.isEmpty == true {
                LibraryNoResultsView(items: "songs", query: model.searchQuery)
            } else {
                SongsListView()
            }
        }
    }
}
