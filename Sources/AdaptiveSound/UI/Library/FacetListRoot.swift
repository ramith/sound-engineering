import LibraryBrowseKit
import SwiftUI

// MARK: - Facet list-root scaffold (S9.6 — the Genres text list; Artists is a tile grid, Years cut)

/// The list-root for a text-list facet category: the load-state machine (spinner / first-run /
/// scanning / facet-empty / failed) over a `List` whose rows are plain Buttons showing "name ·
/// N songs" that OPEN the detail on single-click, and carry the whole-facet queue context menu.
/// (Buttons, not List(selection:)+gesture: on macOS a custom row gesture races the List's built-in
/// selection — the source of an inconsistent select-vs-navigate bug — whereas a Button always fires;
/// this mirrors `AlbumGridView`.)
///
/// A pure VIEW scaffold parameterized by small closures — deliberately generic (unlike the loaders,
/// which are explicit per gate R1) because there is NO hidden concurrency invariant here, only the
/// repeated state-machine + row wiring the three tabs would otherwise copy three times. Centralizing
/// it keeps the facet-empty-vs-"no music" distinction (untagged libraries yield zero artists while
/// songs exist — ui-designer review) correct in ONE place.
struct FacetListRoot<Item: Identifiable>: View {
    let items: [Item]
    let state: LibraryBrowseModel.LoadState
    /// Shown when roots exist + a scan is done but this facet is empty (NOT "No Music Found").
    let empty: FacetListEmpty
    let name: (Item) -> String
    let count: (Item) -> Int
    let ref: (Item) -> LibraryBrowseModel.FacetRef
    let route: (Item) -> LibraryRoute
    let load: () async -> Void
    /// The Filter-field placeholder + the count noun ("Filter Genres" / "genre").
    let filterPlaceholder: String
    let noun: String

    @Environment(LibraryBrowseModel.self) private var model
    /// In-view filter text (narrows the loaded list in place; not sticky across tab switches — the
    /// Apple Music Filter-field behavior).
    @State private var filter = ""

    var body: some View {
        // Keyed on store-readiness so a Library visit BEFORE the async store finishes building
        // loads once it's ready (mirrors AlbumGridView) — not stuck on the nil-store spinner.
        content.task(id: model.isStoreReady) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            if items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                filteredList
            }
        case .loaded:
            if items.isEmpty { empty } else { filteredList }
        case .firstRun:
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .firstRun)
        case .empty:
            // Roots exist, this facet is empty: scanning if a pass is live, else the facet-specific
            // empty (songs may exist but be untagged — NOT the "No Music Found" library-empty state).
            if model.isPopulating { LibraryEmptyStateView(kind: .scanning) } else { empty }
        case let .failed(message):
            LibraryEmptyStateView(kind: .failed(message))
        }
    }

    /// Filter header + the narrowed list (or a "no results" state when the filter matches nothing).
    private var filteredList: some View {
        VStack(spacing: 0) {
            LibraryFilterHeader(count: countLine, filter: $filter, placeholder: filterPlaceholder)
            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                list
            }
        }
    }

    private var filteredItems: [Item] {
        filter.isEmpty ? items : items.filter { FacetTextFilter.matches(name($0), query: filter) }
    }

    private var countLine: String {
        let shown = filteredItems.count
        return "\(shown) \(noun)\(shown == 1 ? "" : "s")"
    }

    private var list: some View {
        List {
            ForEach(filteredItems) { item in row(item) }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    /// Each row is a plain `Button` — the same pattern `AlbumGridView` uses. A Button's single-click
    /// action ALWAYS fires and can't race the List's built-in selection gesture (that race was the
    /// inconsistent select-vs-navigate bug; SwiftUI-on-macOS List selection + a custom row gesture
    /// don't cooperate). Single-click OPENS the facet detail — consistent with Albums + Artists tiles.
    private func row(_ item: Item) -> some View {
        Button {
            model.path.append(route(item))
        } label: {
            FacetRowLabel(name: name(item), count: count(item))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(item)), \(FacetCountLabel.songs(count: count(item)))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play") { Task { await model.playFacet(ref(item)) } }
        .accessibilityAction(named: "Play Next") { Task { await model.playFacetNext(ref(item)) } }
        .accessibilityAction(named: "Add to Queue") { Task { await model.appendFacet(ref(item)) } }
        .contextMenu { FacetQueueActions(ref: ref(item)) }
    }
}
