import LibraryBrowseKit
import SwiftUI

// MARK: - Browse root scaffold (S10.8 — one scaffold for Albums, Artists and Genres)

/// The root of a browse category — Albums, Artists, Genres: the load-state machine (spinner /
/// first-run / scanning / empty / failed), the Filter header over the narrowed items, and "no
/// results" when the filter matches nothing. The body is the section's: the tile grid
/// (`BrowseGrid`) for Albums and Artists, the Genres list until Sprint D puts Genres on the grid.
/// Generalises the S9.6 `FacetListRoot`, so the three roots share one state machine (the
/// facet-empty-vs-"no music" distinction stays correct in ONE place) and one Filter.
struct BrowseGridRoot<Item: Identifiable, Empty: View, Content: View>: View {
    /// The category's visible items, before the filter.
    let items: [Item]
    let state: LibraryBrowseModel.LoadState
    /// Shown when the category is empty while the library is not (`.loaded` / `.empty`).
    let empty: Empty
    /// The count noun ("album") and the Filter placeholder ("Filter Albums").
    let noun: String
    let filterPlaceholder: String
    /// The strings the Filter matches (an album: its title and its artist).
    let filterKeys: (Item) -> [String]
    let load: () async -> Void
    /// The section's body over the filtered items (never empty).
    @ViewBuilder let content: ([Item]) -> Content

    @Environment(LibraryBrowseModel.self) private var model
    /// In-view filter text (narrows the loaded items in place; not sticky across tab switches — the
    /// Apple Music Filter-field behavior).
    @State private var filter = ""

    var body: some View {
        // Keyed on store-readiness so a Library visit BEFORE the async store finishes building
        // loads once it's ready (review S2) — not stuck on the nil-store spinner.
        stateContent.task(id: model.isStoreReady) { await load() }
    }

    @ViewBuilder private var stateContent: some View {
        switch state {
        case .idle, .loading:
            if items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                filtered
            }
        case .loaded:
            if items.isEmpty {
                empty
            } else {
                filtered
            }
        case .firstRun:
            // A scan just kicked off from the first-run CTA flips this to a truthful "scanning"
            // until the items land; otherwise it's the add-a-folder call to action.
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .firstRun)
        case .empty:
            // Roots exist, this category is empty: scanning if a pass is live, else the section's
            // empty state (not the permanent "Scanning…" of the old mapping — review S1).
            if model.isPopulating {
                LibraryEmptyStateView(kind: .scanning)
            } else {
                empty
            }
        case let .failed(message):
            LibraryEmptyStateView(kind: .failed(message))
        }
    }

    /// Filter header + the narrowed body (or "no results"). The filtered items are computed ONCE
    /// here and threaded down — the count line, the empty check and the body share one pass.
    private var filtered: some View {
        let shown = filteredItems
        return VStack(spacing: 0) {
            LibraryFilterHeader(count: countLabel(shown.count), filter: $filter,
                                placeholder: filterPlaceholder)
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            if shown.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                content(shown)
            }
        }
    }

    /// The items narrowed by the filter, in place (order preserved).
    private var filteredItems: [Item] {
        filter.isEmpty ? items : items.filter { FacetTextFilter.matches(filterKeys($0), query: filter) }
    }

    private func countLabel(_ shown: Int) -> String {
        "\(shown) \(noun)\(shown == 1 ? "" : "s")"
    }
}
