import LibraryBrowseKit
import SwiftUI

// MARK: - Browse navigator (S10.8 decision 20)

/// The keyboard cursor and type-to-select of one browse grid (Albums, Artists) or
/// browse list (Genres, until Sprint D puts it on the grid) — the state behind `BrowseKeyboard`.
/// The rules are the Kit's (`GridKeyboardCursor` over `ListKeyboardCursor`, `TypeSelectBuffer`,
/// `ScrollPlacement`); this class only keeps their inputs and turns key results into scrolls.
///
/// Only the cursor is observed (it moves the ring). The layout inputs — tile frames, the column
/// count, the viewport height — change on every scroll or resize and are read only by the keys,
/// so they are kept out of observation: recording them never re-renders the grid.
@MainActor
@Observable
final class BrowseNavigator {
    /// How the root lays its tiles out.
    enum Arrangement {
        /// A tile grid: ←/→ walk reading order; the ring sits outside a tile (`BrowseGridMetrics`).
        case grid
        /// A one-column list: ←/→ bubble; the ring sits just inside the row.
        case list
    }

    let arrangement: Arrangement

    /// The tile the user chose — a navigation key or type-select. Nil until then: the cursor is
    /// the first tile, unanchored.
    private(set) var anchorID: Int64?
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
    @ObservationIgnored private var typeSelectBuffer = TypeSelectBuffer()

    init(arrangement: Arrangement) {
        self.arrangement = arrangement
    }

    // MARK: Cursor and ring

    /// The ONE keyboard cursor over the visible tiles: the ring tile, the tile the keys move from
    /// and the one Return opens.
    func cursor(in rows: [Int64]) -> GridKeyboardCursor<Int64>? {
        GridKeyboardCursor.resolve(rows: rows, anchor: anchorID, columns: columns)
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
        guard let cursor = cursor(in: rows), let target = cursor.target(of: move, in: rows) else { return false }
        claim(target, from: cursor.id, in: rows, proxy: proxy)
        return true
    }

    /// Type-to-select: the first tile whose title starts with the typed prefix becomes the cursor.
    /// No match leaves the cursor where it is.
    func typeSelect<Item: Identifiable>(
        _ characters: String, in items: [Item], title: (Item) -> String, proxy: ScrollViewProxy
    ) where Item.ID == Int64 {
        let prefix = typeSelectBuffer.append(characters, at: .now)
        guard let match = TypeSelectBuffer.firstMatch(for: prefix, in: items, title: title) else { return }
        let rows = items.map(\.id)
        claim(match.id, from: cursor(in: rows)?.id, in: rows, proxy: proxy)
        typeSelectShowsRing = true
    }

    /// The grid's focus changed; leaving it ends the type-select ring.
    func focusChanged(_ focused: Bool) {
        if !focused {
            typeSelectShowsRing = false
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

    /// Makes `target` the (anchored) cursor and scrolls it into view — only as far as needed, and
    /// never flush against the edge where its ring would be cut.
    private func claim(_ target: Int64, from current: Int64?, in rows: [Int64], proxy: ScrollViewProxy) {
        anchorID = target
        let frame = frames[target]
        let forward = (rows.firstIndex(of: target) ?? 0) >= (current.flatMap { rows.firstIndex(of: $0) } ?? 0)
        guard let anchorY = ScrollPlacement.revealAnchorY(
            top: frame.map { Double($0.minY) }, itemHeight: frame.map { Double($0.height) } ?? tileHeight,
            viewportHeight: viewportHeight, margin: revealMargin, forward: forward
        ) else { return }
        proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: anchorY))
    }
}
