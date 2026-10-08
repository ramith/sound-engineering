import LibraryBrowseKit
import SwiftUI

// MARK: - Browse grid metrics (S10.8 D5 — the one grid of Albums, Artists and Genres)

extension DesignSystem {
    /// The browse grid's metrics (`docs/sprints/s10-8-browse-grid-design.md`), in one place so the
    /// three grids — and the keyboard maths over them — can't drift. Derived from existing tokens
    /// where the design derives them (the plate is concentric with the art's `Radius.control`).
    enum BrowseGrid {
        /// The grid area's insets inside the card — the Songs row area's: 12 at each side, so a
        /// tile's plate sits where a row card does and its art lines up with the header text (20),
        /// and 6 above and below.
        static let areaInsetH: CGFloat = 12
        static let areaInsetV: CGFloat = 6
        /// Between tiles, across and down.
        static let spacing: CGFloat = 12
        /// The narrowest a tile gets before a column drops, and the fewest columns there are.
        static let minimumTile: Double = 160
        static let minimumColumns = 2
        /// The plate (hover, keyboard ring) around a tile's content, and its corner radius:
        /// `Radius.control` + the padding, concentric with the art's corners.
        static let platePadding = Spacing.small
        static let plateRadius = Radius.control + platePadding
        /// The title sits this far under the art, and the subtitle this far under the title.
        static let titleGap = Spacing.small
        static let subtitleGap: CGFloat = 2
        /// The no-cover glyph's size, as a share of the art's side.
        static let placeholderGlyphScale: CGFloat = 0.28
        /// The hover Play glyph's size: a share of the art's side, never under the minimum.
        static let playGlyphScale: CGFloat = 0.26
        static let playGlyphMinimum: CGFloat = 20

        /// The columns and tile width for a grid area `areaWidth` wide (`FillGridLayout`).
        static func layout(areaWidth: CGFloat) -> FillGridLayout {
            FillGridLayout(width: Double(areaWidth - 2 * areaInsetH), minimumTile: minimumTile,
                           spacing: Double(spacing), minimumColumns: minimumColumns)
        }

        /// The square art's side in a tile `tileWidth` wide.
        static func artSide(tileWidth: Double) -> CGFloat {
            max(0, CGFloat(tileWidth) - 2 * platePadding)
        }
    }
}
