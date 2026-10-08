import LibraryBrowseKit
import SwiftUI

// MARK: - Browse navigator (S10.8 decision 20 + D6)

/// The keyboard cursor, type-to-select and scroll memory of one browse grid (Albums, Artists) or
/// browse list (Genres, until Sprint D puts it on the grid) — the state behind `BrowseKeyboard`.
/// The rules are the Kit's (`GridCursorState` → `GridKeyboardCursor` over `ListKeyboardCursor`,
/// `ScrollPlacement`); this class only keeps their inputs and turns key results into scrolls.
///
/// Only the cursor is observed (it moves the ring). The layout inputs — tile frames, the column
/// count, the viewport height — change on every scroll or resize and are read only by the keys
/// and by `place`, so they are kept out of observation: recording them never re-renders the grid.
@MainActor
@Observable
final class BrowseNavigator {
    /// How the root lays its tiles out.
    enum Arrangement {
        /// A tile grid: ←/→ walk reading order; the ring sits outside a tile (`BrowseGridMetrics`).
        case grid
        /// A one-column list: ←/→ bubble; the ring sits just outside the row's label, inside the row.
        case list
    }

    let arrangement: Arrangement

    /// The anchor — the tile the user chose: a click, a navigation key, type-select, or the cursor
    /// a return brought back (D6) — and the type-to-select prefix, which every other cursor change
    /// ends (`GridCursorState`).
    private var cursorState = GridCursorState<Int64>()
    /// A type-select hit draws the ring before any navigation key has switched the window to
    /// keyboard mode: typing into the grid IS keyboard use, but the app-wide tracker can't tell it
    /// from typing into a field. Cleared when the grid loses focus.
    private(set) var typeSelectShowsRing = false

    /// Tiles per row, from the laid-out width (`GridLayoutMath.adaptiveColumns`); 1 for a list.
    @ObservationIgnored var columns = 1
    /// The scroll viewport's height.
    @ObservationIgnored var viewportHeight: Double = 0
    /// Every laid-out tile's frame in the scroll view's space (`.scrollView`), forgotten when the
    /// lazy container unloads it — so a stale frame can never claim an off-screen tile is visible.
    @ObservationIgnored private var frames: [Int64: CGRect] = [:]

    init(arrangement: Arrangement) {
        self.arrangement = arrangement
    }

    // MARK: Cursor and ring

    /// The ONE keyboard cursor over the visible tiles: the ring tile, the tile the keys move from
    /// and the one Return opens.
    func cursor(in rows: [Int64]) -> GridKeyboardCursor<Int64>? {
        cursorState.cursor(in: rows, columns: columns)
    }

    /// The tile wearing the ring, or nil: the cursor while the grid holds focus in keyboard mode
    /// (or right after a type-select hit) — the A3 rule of every custom list.
    func ringID(in rows: [Int64], focused: Bool, keyboardMode: Bool) -> Int64? {
        focused && (keyboardMode || typeSelectShowsRing) ? cursor(in: rows)?.id : nil
    }

    /// The rows a Page Up / Down moves: the whole rows the viewport shows at the laid-out pitch.
    var pageRows: Int {
        let pitch = GridLayoutMath.rowPitch(tops: frames.values.map { Double($0.minY) }) ?? tileHeight
        return GridLayoutMath.rowsPerPage(viewportHeight: viewportHeight, rowPitch: pitch)
    }

    /// Any laid-out tile's height (they are all one height), or 0 before the first layout.
    private var tileHeight: Double {
        frames.values.first.map { Double($0.height) } ?? 0
    }

    // MARK: Keys

    /// A navigation key: moves the cursor (claiming the tile) and scrolls it into view. False when
    /// the key should bubble.
    func move(_ move: GridKeyboardCursor<Int64>.Move, in rows: [Int64], proxy: ScrollViewProxy) -> Bool {
        let current = cursor(in: rows)?.id
        guard let target = cursorState.move(move, in: rows, columns: columns) else { return false }
        reveal(target, from: current, in: rows, proxy: proxy)
        return true
    }

    /// Type-to-select: the first tile whose title starts with the typed prefix becomes the cursor.
    /// No match leaves the cursor where it is.
    func typeSelect<Item: Identifiable>(
        _ characters: String, in items: [Item], title: (Item) -> String, proxy: ScrollViewProxy
    ) where Item.ID == Int64 {
        let rows = items.map(\.id)
        let current = cursor(in: rows)?.id
        guard let match = cursorState.typeSelect(characters, at: .now, in: items, title: title) else { return }
        reveal(match, from: current, in: rows, proxy: proxy)
        typeSelectShowsRing = true
    }

    /// The grid's focus changed; leaving it ends the type-select ring and the typed prefix.
    func focusChanged(_ focused: Bool) {
        if !focused {
            typeSelectShowsRing = false
            cursorState.endTyping()
        }
    }

    // MARK: Opening a tile, and the place (D6)

    /// A tile is being opened (a click or Return): it becomes the cursor, and the place to come
    /// back to is pinned on it. The grid held focus — a click focuses it, as a row click does.
    func opening(_ id: Int64, category: LibraryCategory, rows: [Int64]) -> BrowsePlace? {
        cursorState.choose(id)
        return place(category: category, rows: rows, focused: true)
    }

    /// Where the grid is now (`BrowsePlace`): pinned on the cursor tile when it is fully visible,
    /// else on the first fully visible tile — or, with nothing laid out, on the cursor, centred.
    /// Nil only with neither.
    func place(category: LibraryCategory, rows: [Int64], focused: Bool) -> BrowsePlace? {
        let shown = Set(rows)
        let tiles = frames.filter { shown.contains($0.key) }.map { id, frame in
            ScrollPlacement.Tile(id: id, top: frame.minY, leading: frame.minX, height: frame.height)
        }
        let cursorID = cursorState.anchor.flatMap { shown.contains($0) ? $0 : nil }
        let point = ScrollPlacement.restorePoint(tiles: tiles, viewportHeight: viewportHeight, preferred: cursorID)
            ?? cursorID.map { (id: $0, anchorY: 0.5) }
        guard let point else { return nil }
        return BrowsePlace(category: category, scrollTileID: point.id, anchorY: point.anchorY,
                           cursorID: cursorID, wasFocused: focused)
    }

    /// Puts the grid back at `place`: the cursor on its tile and the pinned tile at the same height.
    /// A tile that left the library in between is skipped (the grid then starts at the top).
    func restore(_ place: BrowsePlace, rows: [Int64], proxy: ScrollViewProxy) {
        if let cursorID = place.cursorID, rows.contains(cursorID) {
            cursorState.choose(cursorID)
        }
        if rows.contains(place.scrollTileID) {
            proxy.scrollTo(place.scrollTileID, anchor: UnitPoint(x: 0.5, y: place.anchorY))
        }
    }

    // MARK: Layout inputs

    func record(_ frame: CGRect, for id: Int64) {
        frames[id] = frame
    }

    func forget(_ id: Int64) {
        frames[id] = nil
    }

    // MARK: Private

    /// The room kept between the cursor tile and the viewport edge when scrolling it into view:
    /// the grid's ring is drawn outside the tile, so the tile stops short of the edge by more.
    private var revealMargin: Double {
        switch arrangement {
        case .grid: BrowseGridMetrics.ringOutset + 2
        case .list: 4
        }
    }

    /// Scrolls the new cursor `target` into view — only as far as needed, and never flush against
    /// the edge where its ring would be cut. `current` (the cursor before) gives the direction for a
    /// tile not laid out yet.
    private func reveal(_ target: Int64, from current: Int64?, in rows: [Int64], proxy: ScrollViewProxy) {
        let frame = frames[target]
        let forward = (rows.firstIndex(of: target) ?? 0) >= (current.flatMap { rows.firstIndex(of: $0) } ?? 0)
        guard let anchorY = ScrollPlacement.revealAnchorY(
            top: frame.map { Double($0.minY) }, itemHeight: frame.map { Double($0.height) } ?? tileHeight,
            viewportHeight: viewportHeight, margin: revealMargin, forward: forward
        ) else { return }
        proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchorY))
    }
}
