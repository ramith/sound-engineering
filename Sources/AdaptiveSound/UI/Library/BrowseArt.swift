import LibraryBrowseKit
import SwiftUI

// MARK: - Browse art (S10.8 D5 — the one art view of the browse tiles)

/// A browse tile's square art, by the one rule (`CoverArrangement`): four or more covers → a 2×2
/// mosaic (a genre); one to three → the first cover; none → the section's placeholder. A mosaic
/// quarter whose cover is missing shows the placeholder's wash alone. `Radius.control` corners and a
/// 0.5-pt hairline, as every cover. It fills its tile's width (the tiles fill the grid's columns),
/// so `side` — the laid-out side — only sizes the glyph and the decode. Hidden from VoiceOver: the
/// tile carries the label.
struct BrowseArt: View {
    let keys: [String]
    let side: CGFloat
    let placeholderSymbol: String
    /// The browse model, as a plain value — see `ArtworkThumbnail.model`.
    let model: LibraryBrowseModel

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { art }
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                    .strokeBorder(DesignSystem.Color.hairline, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var art: some View {
        switch CoverArrangement(keys: keys) {
        case let .mosaic(quarters):
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    quarter(quarters[0])
                    quarter(quarters[1])
                }
                HStack(spacing: 0) {
                    quarter(quarters[2])
                    quarter(quarters[3])
                }
            }
        case let .single(key):
            cover(key) { BrowseArtPlaceholder(symbol: placeholderSymbol, side: side) }
        case .placeholder:
            BrowseArtPlaceholder(symbol: placeholderSymbol, side: side)
        }
    }

    /// One quarter of a mosaic: an equal share of the square, its cover clipped to it.
    private func quarter(_ key: String) -> some View {
        Color.clear
            .overlay { cover(key) { DesignSystem.Color.hoverWash } }
            .clipped()
    }

    /// A cover decoded at the art's FULL side, even in a mosaic quarter: the thumbnail cache keeps
    /// one size per key, and the same album's tile on the Albums grid shows it full size.
    private func cover<Placeholder: View>(_ key: String,
                                          @ViewBuilder placeholder: () -> Placeholder) -> some View {
        ArtworkThumbnail(key: key, pixelSide: side, model: model, placeholder: placeholder)
    }
}
