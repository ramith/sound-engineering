import Foundation

// MARK: - Browse place (S10.8 D6 — the grid keeps its scroll position)

/// Where a browse root's grid (Albums, Artists) or list (Genres) was when it left the screen — for
/// an album / artist / genre page, or another tab — so coming back puts it where it was, with the
/// keyboard cursor on the same tile. The grid is destroyed under a drill-down (the detail replaces
/// it), so this lives on `LibraryBrowseModel` and is used once, by the next appearance of the same
/// category's root. A rail jump clears it (`selectCategory`): that starts the root fresh.
///
/// The scroll position is kept as a TILE and its height on screen, not as a content offset, so it
/// survives a window resize in between (the columns change, the tile stays put) and a library
/// change that moves the tile (`ScrollPlacement.restorePoint`).
struct BrowsePlace {
    let category: LibraryCategory
    /// The tile the scroll position is pinned to: the keyboard cursor when it was on screen (always
    /// so for a tile just opened), else the first fully visible tile.
    let scrollTileID: Int64
    /// `scrollTo`'s anchor for `scrollTileID` — its height on screen, 0 = top, 1 = bottom.
    let anchorY: Double
    /// The keyboard cursor: the tile just opened, else the anchor the user last chose, if any.
    let cursorID: Int64?
    /// The grid or list held keyboard focus (it takes it back, so the arrows go on from the tile).
    let wasFocused: Bool
}
