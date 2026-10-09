import LibraryBrowseKit
import SwiftUI

// MARK: - Browse root scaffold (S10.8 — one scaffold for Albums, Artists and Genres)

/// The root of a browse category — Albums, Artists, Genres: the Library card roots' load states
/// (`LibraryLoadStateView`), then the card header (`LibraryCardHeader` — title, count line, Filter
/// pill) over the tile grid (`BrowseGrid`) of the narrowed items, or "no results" when the filter
/// matches nothing. Generalises the S9.6 `FacetListRoot`; each section supplies only data — its
/// items, noun, empty state, filter keys, title, loader and each item's `BrowseTileContent` — so the
/// three grids can't drift.
///
/// The Filter text lives on the model (`browseFilter`): it survives the drill-down and comes back
/// with the grid's place (D6); a rail jump clears it.
struct BrowseGridRoot<Item: Identifiable, Empty: View>: View where Item.ID == Int64 {
    let category: LibraryCategory
    /// The category's visible items, before the filter.
    let items: [Item]
    let state: LibraryBrowseModel.LoadState
    /// The count noun, singular: "album".
    let noun: String
    /// Shown when the category is empty while the library is not (`.loaded` / `.empty`).
    let empty: Empty
    /// The strings the Filter matches (an album: its title and its artist).
    let filterKeys: (Item) -> [String]
    /// The title type-to-select matches — a plain read, so a key press never builds every tile's
    /// content.
    let title: (Item) -> String
    let load: () async -> Void
    let tile: (Item) -> BrowseTileContent

    @Environment(LibraryBrowseModel.self) private var model
    /// The card's one focus value (`CardFocus`, K1): the Filter pill is `.filter`, the grid
    /// `.content` — so Esc in the filter lands on the grid, even one "no results" had replaced.
    @FocusState private var focus: CardFocus?

    var body: some View {
        LibraryLoadStateView(state: state, isEmpty: items.isEmpty) {
            empty
        } content: {
            filtered
        }
        // Keyed on store-readiness so a Library visit BEFORE the async store finishes building
        // loads once it's ready (review S2) — not stuck on the nil-store spinner.
        .task(id: model.isStoreReady) { await load() }
    }

    /// The card header + the narrowed grid (or "no results"). The filtered items are computed ONCE
    /// here and threaded down — the count line, the empty check and the grid share one pass.
    private var filtered: some View {
        @Bindable var model = model
        let query = model.browseFilter
        let isFiltering = FacetTextFilter.isActive(query)
        let shown = isFiltering ? items.filter { FacetTextFilter.matches(filterKeys($0), query: query) } : items
        return VStack(spacing: 0) {
            LibraryCardHeader(title: category.title,
                              count: FacetCountLabel.count(shown.count, noun: noun, filtered: isFiltering),
                              filter: $model.browseFilter, filterPrompt: "Filter \(category.title)",
                              focus: $focus)
            if shown.isEmpty {
                LibraryNoResultsView(items: "\(noun)s", query: query)
            } else {
                BrowseGrid(category: category, items: shown, title: title, tile: tile, focus: $focus)
            }
        }
    }
}
