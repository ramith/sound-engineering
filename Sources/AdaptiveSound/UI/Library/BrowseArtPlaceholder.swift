import SwiftUI

// MARK: - Browse art placeholder (S10.8 D5 — a tile with no cover)

/// The art of a browse tile with no cover: the `hoverWash` fill — the resting small-control wash,
/// which reads on the card in both appearances (the old `card` fill was a hole in dark and white
/// on white in light) — with the section's glyph (`LibraryCategory.tilePlaceholderSymbol`) in
/// `labelTertiary`. No monograms: initials break on CJK, RTL and emoji names. Fills its frame.
struct BrowseArtPlaceholder: View {
    let symbol: String
    /// The art's side, which sizes the glyph.
    let side: CGFloat

    var body: some View {
        DesignSystem.Color.hoverWash
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: max(12, side * DesignSystem.BrowseGrid.placeholderGlyphScale)))
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
    }
}
