import LibraryBrowseKit
import SwiftUI

// MARK: - Facet list (S9.6 — the Genres text list, until Sprint D puts Genres on the browse grid)

/// The Genres body under `BrowseGridRoot`: rows of plain Buttons showing "name · N songs" that
/// OPEN the detail on single-click and carry the whole-facet queue context menu.
///
/// A `ScrollView` + `LazyVStack`, like every other custom list (Songs, the queue, the rail) — not a
/// SwiftUI `List`: an NSTableView-backed `List` takes key focus and handles the arrows itself, so
/// the keys below could be eaten, or the list become two Tab stops. It draws what the `.inset`
/// `List` drew, measured offscreen and pixel-identical on all four channels in dark and light: a
/// 10-pt inset above and below, 24-pt rows (the label, 4 pt above and below, 16 pt each side) and
/// a 1-pt `.separator` line under every row but the last, inset with the label.
///
/// Keyboard (decision 20): the grids' `BrowseKeyboard` as a one-column list — ↑/↓, Home / End,
/// Page Up / Down, type-to-select, Return opens — with the teal ring on the cursor row in place of
/// the system focus effect, and the list's place kept across a drill-down (D6).
struct FacetList<Item: Identifiable>: View where Item.ID == Int64 {
    let category: LibraryCategory
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

    /// The `.inset` `List`'s inset above the first row and below the last.
    private static var listInset: CGFloat {
        10
    }

    /// Around the label inside a row — the `.inset` `List`'s row insets. The row is the Button, so
    /// the whole 24-pt row is the click target, not just the label's line.
    private static var rowInsets: EdgeInsets {
        EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    }

    /// The ring: 3 pt above and below the label, 6 pt to each side — just inside the row.
    private static var ringInsets: EdgeInsets {
        EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10)
    }

    var body: some View {
        let ringID = navigator.ringID(in: items.map(\.id), focused: focused, keyboardMode: showsKeyboardFocus)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item, isKeyboardCursor: item.id == ringID, isLast: item.id == items.last?.id)
                    }
                }
                .padding(.vertical, Self.listInset)
            }
            .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { navigator.viewportHeight = $0 }
            .modifier(BrowseKeyboard(category: category, items: items, title: name, navigator: navigator,
                                     focused: $focused, proxy: proxy, open: open))
        }
    }

    /// Each row is a plain `Button` — the pattern the grid tiles use; single-click OPENS the facet
    /// detail, as the tiles do. No focus stop of its own: the list is one stop whose keys move the
    /// ring.
    private func row(_ item: Item, isKeyboardCursor: Bool, isLast: Bool) -> some View {
        Button {
            open(item)
        } label: {
            FacetRowLabel(name: name(item), count: count(item))
                .padding(Self.rowInsets)
                .contentShape(Rectangle())
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
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)
                    .padding(.horizontal, Self.rowInsets.leading)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            Color.clear
                .keyboardCursorRing(isKeyboardCursor, cornerRadius: DesignSystem.Radius.control)
                .padding(Self.ringInsets)
        }
        // The row's frame on screen, for scroll-into-view and the place (D6).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
            navigator.record(frame, for: item.id)
        }
        .onDisappear { navigator.forget(item.id) }
    }

    /// Opens a row's page — a click or Return — remembering the place to come back to (D6).
    private func open(_ item: Item) {
        model.browsePlace = navigator.opening(item.id, category: category, rows: items.map(\.id))
        model.path.append(route(item))
    }
}
