import SwiftUI

// MARK: - Songs list (S9.5)

/// The Library's default landing: a flat, full-library `Table` of every track over the
/// in-memory full-load set (`LibraryBrowseModel.songs`, OD-1). Header + customizable-column table
/// (`SongsHeader` + `SongsTable`), the composite default order, double-click / Return
/// play-from-row, and the "N songs · total" count.
///
/// State handling mirrors `AlbumGridView`: a `.task(id:)` keyed on store-readiness kicks the
/// full-load, and `.onChange(of: libraryRevision)` (in `LibraryTabView`) reloads once per pass.
/// Header + table are shown only when there ARE rows; otherwise the spinner / empty / first-run /
/// scanning / failed states delegate to `LibraryEmptyStateView` (no new case).
struct SongsView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        content
            // Keyed on store-readiness so a Library visit BEFORE the async store finishes building
            // reloads once it's ready (mirrors AlbumGridView / review S2) — not a stuck spinner.
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

    @ViewBuilder private var content: some View {
        switch model.songsState {
        case .idle, .loading:
            if model.songs.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                songsList // keep showing cached rows while a refresh is in flight
            }
        case .loaded:
            // `.loaded` but empty means every track was removed — a genuine empty library.
            if model.songs.isEmpty { LibraryEmptyStateView(kind: .emptyLibrary) } else { songsList }
        case .firstRun:
            // A scan kicked off from the first-run CTA flips this to a truthful "scanning" until
            // rows land; otherwise it's the add-a-folder call to action.
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .firstRun)
        case .empty:
            // Roots exist, zero tracks: scanning if a pass is live, else a genuine "no music".
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .emptyLibrary)
        case let .failed(message):
            LibraryEmptyStateView(kind: .failed(message))
        }
    }

    /// Header + hairline + table — shown only when there is content (design §10.3). When a filter
    /// is active but matches nothing (`matchedIDs == []`), the table is replaced by the zero-results
    /// view while the header (field + "0 results") stays shown — DISTINCT from the empty-library
    /// state, which is reached only when there's genuinely no library content (§3.3/§10.3).
    private var songsList: some View {
        VStack(spacing: 0) {
            SongsHeader()
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            if model.matchedIDs?.isEmpty == true {
                zeroResults
            } else {
                SongsTable()
            }
        }
    }

    /// Filtered-to-nothing state (§3.3). Don't animate the swap in/out (Table diff jank / §11);
    /// `ContentUnavailableView` respects Reduce Motion natively.
    private var zeroResults: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No songs match “\(model.searchQuery)”.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
