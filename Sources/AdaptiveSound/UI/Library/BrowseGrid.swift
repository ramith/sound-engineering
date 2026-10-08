import SwiftUI

// MARK: - Browse grid (S10.8 — the one tile grid of Albums and Artists)

/// The full-width adaptive tile grid of a browse root — Albums and Artists today, Genres from
/// Sprint D — with the keyboard wired once (`BrowseKeyboard`: arrows, Home / End, Page Up / Down,
/// type-to-select, Return). Single-click a tile → OPEN (pushes the section's route); the Play
/// verbs come from the hover button and the context menu. The
/// section supplies only data: its tiles' content, title, route, Play and queue actions.
///
/// Today's layout, unchanged: fixed `tileSide` tiles centred in adaptive columns of up to
/// `columnMaximum` (`BrowseGridMetrics`). The column count the arrow keys step by is computed from
/// the laid-out width with the same rule SwiftUI's adaptive `GridItem` uses.
struct BrowseGrid<Item: Identifiable, Cell: View, Actions: View>: View where Item.ID == Int64 {
    /// The visible (filtered) tiles, in display order.
    let items: [Item]
    /// The type-to-select key.
    let title: (Item) -> String
    let route: (Item) -> LibraryRoute
    let play: @MainActor (Item) async -> Void
    @ViewBuilder let cell: (Item) -> Cell
    @ViewBuilder let actions: (Item) -> Actions

    @Environment(LibraryBrowseModel.self) private var model
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    @State private var navigator = BrowseNavigator(arrangement: .grid)
    @FocusState private var focused: Bool

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: BrowseGridMetrics.tileSide, maximum: BrowseGridMetrics.columnMaximum),
                  spacing: BrowseGridMetrics.columnSpacing)]
    }

    var body: some View {
        let ringID = navigator.ringID(in: items.map(\.id), focused: focused, keyboardMode: showsKeyboardFocus)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: BrowseGridMetrics.rowSpacing) {
                    ForEach(items) { item in
                        tile(item, isKeyboardCursor: item.id == ringID)
                    }
                }
                .padding(BrowseGridMetrics.inset)
                .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { width in
                    navigator.columns = BrowseGridMetrics.columns(width: width)
                }
            }
            .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { navigator.viewportHeight = $0 }
            .modifier(BrowseKeyboard(items: items, title: title, navigator: navigator,
                                     focused: $focused, proxy: proxy, open: open))
        }
    }

    private func tile(_ item: Item, isKeyboardCursor: Bool) -> some View {
        BrowseTile(
            side: BrowseGridMetrics.tileSide,
            isKeyboardCursor: isKeyboardCursor,
            open: { open(item) },
            play: { await play(item) },
            cell: { cell(item) },
            actions: { actions(item) }
        )
        // The tile's frame on screen, for scroll-into-view — dropped when the lazy grid unloads it.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
            navigator.record(frame, for: item.id)
        }
        .onDisappear { navigator.forget(item.id) }
    }

    /// Opens a tile's page — a click or Return.
    private func open(_ item: Item) {
        model.path.append(route(item))
    }
}
