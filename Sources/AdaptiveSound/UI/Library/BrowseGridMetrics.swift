import LibraryBrowseKit
import SwiftUI

// MARK: - Browse grid metrics (S10.8 — today's Albums / Artists grid, in one place)

/// The browse grid's metrics, shared by Albums and Artists (and Genres from Sprint D) so the three
/// grids — and the keyboard maths over them — can't drift. These are TODAY's values, moved here
/// unchanged; Sprint D's restyle replaces them (the design's fill-width columns and tile plate).
enum BrowseGridMetrics {
    /// The tile (and its square art) side.
    static let tileSide: CGFloat = 168
    /// The adaptive column's minimum is the tile side — a narrower column would clip the tile
    /// (review S1/layout) — and its maximum 200: wider columns centre the tile.
    static let columnMaximum: CGFloat = 200
    static let columnSpacing: CGFloat = 16
    static let rowSpacing = DesignSystem.Spacing.large
    /// The grid's inset inside the scroll view, every side.
    static let inset = DesignSystem.Spacing.medium

    /// The keyboard ring sits this far OUTSIDE the tile (there is no tile plate yet to draw it on;
    /// the gaps between tiles hold it), concentric with the art's corners.
    static let ringOutset: CGFloat = 6
    static let ringCornerRadius = DesignSystem.Radius.control + ringOutset

    /// The columns the grid lays out at a laid-out width (the grid plus its insets).
    static func columns(width: Double) -> Int {
        GridLayoutMath.adaptiveColumns(width: width - 2 * Double(inset), minimum: tileSide, spacing: columnSpacing)
    }
}
