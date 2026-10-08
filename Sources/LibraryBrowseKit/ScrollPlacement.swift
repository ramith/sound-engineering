// MARK: - ScrollPlacement (S10.8 D6 + decision 20 — where a scroll puts a tile)

/// Where `ScrollViewProxy.scrollTo(_:anchor:)` puts an item, in both directions: the anchor that
/// lands a tile at a given height (D6: the grid comes back where it was), and the anchor that
/// brings the keyboard cursor fully into view with room for its ring (only when it isn't already).
///
/// `scrollTo` aligns the anchor point of the item with the same point of the viewport, so an item
/// of height `h` in a viewport of height `H` lands with its top at `y × (H − h)` — checked
/// offscreen on a `LazyVGrid` and on a `List`, including tiles far outside the laid-out range.
/// Positions are in the scroll view's own space (`.scrollView`: 0 = the viewport's top edge).
public enum ScrollPlacement {
    /// A laid-out tile's frame in the scroll view's space.
    public struct Tile<ID: Equatable> {
        let id: ID
        let top: Double
        let leading: Double
        let height: Double

        public init(id: ID, top: Double, leading: Double, height: Double) {
            self.id = id
            self.top = top
            self.leading = leading
            self.height = height
        }
    }

    /// The anchor `y` that puts an item's top `top` points below the viewport's top edge, clamped to
    /// 0…1 so the item is never left partly off screen.
    static func anchorY(top: Double, itemHeight: Double, viewportHeight: Double) -> Double {
        let travel = viewportHeight - itemHeight
        guard travel > 0 else { return 0 } // taller than the viewport: show its top
        return min(max(top / travel, 0), 1)
    }

    /// Scroll-into-view for the cursor tile: nil when it is fully visible with `margin` to spare at
    /// both edges (no scroll — the native "only as far as needed"); otherwise the anchor that brings
    /// it `margin` inside the nearer edge. `top` is nil for a tile that is not laid out (far off
    /// screen) — then the direction of travel picks the edge: `forward` = the bottom one.
    public static func revealAnchorY(
        top: Double?, itemHeight: Double, viewportHeight: Double, margin: Double, forward: Bool
    ) -> Double? {
        let lowestTop = viewportHeight - margin - itemHeight
        if let top, top >= margin, top <= lowestTop {
            return nil
        }
        let towardBottom = top.map { $0 > lowestTop } ?? forward
        return anchorY(top: towardBottom ? lowestTop : margin, itemHeight: itemHeight, viewportHeight: viewportHeight)
    }

    /// The tile to restore the scroll position on (D6), with its anchor: `preferred` (the cursor)
    /// when it is fully visible, else the first fully visible tile in reading order (top, then
    /// leading), else the laid-out tile nearest the top edge. Nil when nothing is laid out.
    public static func restorePoint<ID>(
        tiles: [Tile<ID>], viewportHeight: Double, preferred: ID?
    ) -> (id: ID, anchorY: Double)? {
        let visible = tiles.filter { $0.top >= 0 && $0.top + $0.height <= viewportHeight }
        let chosen = visible.first { $0.id == preferred }
            ?? visible.min { ($0.top, $0.leading) < ($1.top, $1.leading) }
            ?? tiles.min { abs($0.top) < abs($1.top) }
        return chosen.map { ($0.id, anchorY(top: $0.top, itemHeight: $0.height, viewportHeight: viewportHeight)) }
    }
}
