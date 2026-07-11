import LibraryBrowseKit
import SwiftUI

// MARK: - Facet list-root scaffold (S9.6 — shared by Artists / Genres / Years)

/// The list-root for a facet category: the load-state machine (spinner / first-run / scanning /
/// facet-empty / failed) over a selectable, type-selectable `List` whose rows show "name · N songs",
/// open the detail on double-click / Return, and carry the whole-facet queue context menu.
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

    @Environment(LibraryBrowseModel.self) private var model
    @State private var selection: Item.ID?

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
                list
            }
        case .loaded:
            if items.isEmpty { empty } else { list }
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

    private var list: some View {
        List(selection: $selection) {
            ForEach(items) { item in row(item) }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onKeyPress(.return) { openSelected(); return .handled }
    }

    private func row(_ item: Item) -> some View {
        FacetRowLabel(name: name(item), count: count(item))
            .onTapGesture(count: 2) { model.path.append(route(item)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name(item)), \(FacetCountLabel.songs(count: count(item)))")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open") { model.path.append(route(item)) }
            .accessibilityAction(named: "Play") { Task { await model.playFacet(ref(item)) } }
            .accessibilityAction(named: "Play Next") { Task { await model.playFacetNext(ref(item)) } }
            .accessibilityAction(named: "Add to Queue") { Task { await model.appendFacet(ref(item)) } }
            .contextMenu { FacetQueueActions(ref: ref(item)) }
    }

    private func openSelected() {
        guard let id = selection, let item = items.first(where: { $0.id == id }) else { return }
        model.path.append(route(item))
    }
}
