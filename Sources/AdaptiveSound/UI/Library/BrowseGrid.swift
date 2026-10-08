import LibraryBrowseKit
import SwiftUI

// MARK: - Browse grid (S10.8 D5 — the one tile grid of Albums, Artists and Genres)

/// The browse grid: tiles that FILL the card's width (`FillGridLayout` — at least 160 pt, at least
/// two columns, no gutter left over), 12 pt apart both ways inside the Songs row area's insets,
/// with the keyboard wired once (`BrowseKeyboard`: arrows, Home / End, Page Up / Down,
/// type-to-select, Return) and the place it returns to (D6). Single-click a tile → OPEN (pushes its
/// page); the Play verbs come from the hover button, VoiceOver's actions and the context menu.
/// The section supplies only data: each item's `BrowseTileContent`.
///
/// The width is read in the same layout pass (a `GeometryReader`), so the first frame already has
/// its real columns — a D6 restore scrolls a grid that won't re-flow under it. The columns are
/// flexible, so a legacy (always-shown) scroll bar narrows the tiles instead of clipping them.
struct BrowseGrid<Item: Identifiable>: View where Item.ID == Int64 {
    let category: LibraryCategory
    /// The visible (filtered) tiles, in display order.
    let items: [Item]
    let tile: (Item) -> BrowseTileContent

    @Environment(LibraryBrowseModel.self) private var model
    /// Draw the cursor ring only while the user navigates by keyboard (A-review).
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus
    @State private var navigator = BrowseNavigator()
    @FocusState private var focused: Bool
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetFixture.swift`): the tile it puts the cursor on.
        @Environment(\.sheetGridStates) private var sheetGridStates
    #endif

    private typealias Metrics = DesignSystem.BrowseGrid

    var body: some View {
        GeometryReader { geometry in
            let layout = Metrics.layout(areaWidth: geometry.size.width)
            let artSide = Metrics.artSide(tileWidth: layout.tileWidth)
            let ringID = navigator.ringID(in: items.map(\.id), focused: focused, keyboardMode: showsKeyboardFocus)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Self.columns(layout.columns), spacing: Metrics.spacing) {
                        ForEach(items) { item in
                            BrowseTile(content: tile(item), artSide: artSide,
                                       placeholderSymbol: category.tilePlaceholderSymbol,
                                       isKeyboardCursor: item.id == ringID, open: { open(item) })
                                // The tile's frame on screen, for scroll-into-view and the place
                                // (D6) — dropped when the lazy grid unloads it.
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
                                    navigator.record(frame, for: item.id)
                                }
                                .onDisappear { navigator.forget(item.id) }
                        }
                    }
                    .padding(.horizontal, Metrics.areaInsetH)
                    .padding(.vertical, Metrics.areaInsetV)
                }
                .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { navigator.viewportHeight = $0 }
                .onChange(of: layout.columns, initial: true) { _, columns in navigator.columns = columns }
                .modifier(BrowseKeyboard(category: category, items: items, title: { tile($0).title },
                                         navigator: navigator, focused: $focused, proxy: proxy, open: open))
                #if DEBUG
                    // Picture-sheet states variant: focus, with the cursor on the fixture's tile.
                    .sheetFocusSeed(.grid) {
                        if let cursor = items.first(where: { tile($0).ref == sheetGridStates.cursor }) {
                            navigator.seedCursor(cursor.id)
                        }
                        focused = true
                    }
                #endif
            }
        }
    }

    /// `count` equal, flexible columns, 12 pt apart.
    private static func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.spacing), count: count)
    }

    /// Opens a tile's page — a click or Return — remembering the place to come back to (D6).
    private func open(_ item: Item) {
        model.browsePlace = navigator.opening(item.id, category: category, rows: items.map(\.id))
        model.path.append(tile(item).ref.route)
    }
}
