import LibraryBrowseKit
import SwiftUI

// MARK: - Facet list (S9.6 — the Genres text list, until Sprint D puts Genres on the browse grid)

/// The Genres body under `BrowseGridRoot`: a `List` whose rows are plain Buttons showing "name ·
/// N songs" that OPEN the detail on single-click and carry the whole-facet queue context menu.
/// (Buttons, not List(selection:)+gesture: on macOS a custom row gesture races the List's built-in
/// selection — the source of an inconsistent select-vs-navigate bug — whereas a Button always fires;
/// this mirrors the browse grid's tiles.)
///
/// Keyboard (decision 20): the grids' `BrowseKeyboard` as a one-column list — ↑/↓, Home / End,
/// Page Up / Down, type-to-select, Return opens — with the teal ring on the cursor row in place of
/// the system focus effect.
struct FacetList<Item: Identifiable>: View where Item.ID == Int64 {
    /// The visible (filtered) items, in display order.
    let items: [Item]
    let name: (Item) -> String
    let count: (Item) -> Int
    let ref: (Item) -> LibraryBrowseModel.FacetRef
    let route: (Item) -> LibraryRoute

    @Environment(LibraryBrowseModel.self) private var model
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    @State private var navigator = BrowseNavigator(arrangement: .list)
    @FocusState private var focused: Bool

    /// The ring sits just outside the row's label — inside the row's own height and inset.
    private static var ringInsets: EdgeInsets {
        EdgeInsets(top: -3, leading: -6, bottom: -3, trailing: -6)
    }

    var body: some View {
        let ringID = navigator.ringID(in: items.map(\.id), focused: focused, keyboardMode: showsKeyboardFocus)
        ScrollViewReader { proxy in
            List {
                ForEach(items) { item in row(item, isKeyboardCursor: item.id == ringID) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { navigator.viewportHeight = $0 }
            .modifier(BrowseKeyboard(items: items, title: name, navigator: navigator,
                                     focused: $focused, proxy: proxy, open: open))
        }
    }

    /// Each row is a plain `Button` — the pattern the grid tiles use. A Button's single-click action
    /// ALWAYS fires and can't race the List's built-in selection gesture (that race was the
    /// inconsistent select-vs-navigate bug). Single-click OPENS the facet detail, as the tiles do.
    /// No focus stop of its own: the list is one stop whose keys move the ring.
    private func row(_ item: Item, isKeyboardCursor: Bool) -> some View {
        Button {
            open(item)
        } label: {
            FacetRowLabel(name: name(item), count: count(item))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(item)), \(FacetCountLabel.songs(count: count(item)))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play") { Task { await model.playFacet(ref(item)) } }
        .accessibilityAction(named: "Play Next") { Task { await model.playFacetNext(ref(item)) } }
        .accessibilityAction(named: "Add to Queue") { Task { await model.appendFacet(ref(item)) } }
        .contextMenu { FacetQueueActions(ref: ref(item)) }
        .overlay {
            Color.clear
                .padding(Self.ringInsets)
                .keyboardCursorRing(isKeyboardCursor, cornerRadius: DesignSystem.Radius.control)
        }
        // The row's frame on screen, for scroll-into-view.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
            navigator.record(frame, for: item.id)
        }
        .onDisappear { navigator.forget(item.id) }
    }

    /// Opens a row's page — a click or Return.
    private func open(_ item: Item) {
        model.path.append(route(item))
    }
}
