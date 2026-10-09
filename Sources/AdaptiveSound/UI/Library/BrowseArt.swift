import LibraryBrowseKit
import SwiftUI

// MARK: - Browse art (S10.8 D5 — the one art view of the browse tiles)

/// A browse tile's square art, by the one rule (`CoverArrangement`): four or more covers → a 2×2
/// mosaic (a genre); one to three → the first cover; none → the section's placeholder.
/// `Radius.control` corners and a 0.5-pt hairline, as every cover. It fills its tile's width (the
/// tiles fill the grid's columns), so `side` — the laid-out side — only sizes the glyph and the
/// decode. Hidden from VoiceOver: the tile carries the label.
///
/// A cover that can't be shown (its cache file deleted or unreadable — `ArtworkThumbnail`'s
/// failure) drops out and the arrangement rebuilds from the rest: a mosaic that loses one becomes
/// the next cover full size, and a tile that loses all of them shows the placeholder with its glyph
/// — never a blank tile. While a quarter is still loading it shows the placeholder's wash.
struct BrowseArt: View {
    let keys: [String]
    let side: CGFloat
    let placeholderSymbol: String
    /// The browse model, as a plain value — see `ArtworkThumbnail.model`.
    let model: LibraryBrowseModel

    /// The keys whose covers failed, for the keys they were reported against.
    @State private var failed: Set<String> = []

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
            // New covers for this tile (a library change, a reused tile): every key gets a chance.
            .onChange(of: keys) { failed = [] }
    }

    @ViewBuilder private var art: some View {
        switch CoverArrangement(keys: keys.filter { !failed.contains($0) }) {
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

    /// A cover decoded at the art's FULL side, even in a mosaic quarter, so the album's own tile
    /// on the Albums grid is served by the same decode. A failure drops the key (above).
    private func cover<Placeholder: View>(_ key: String,
                                          @ViewBuilder placeholder: () -> Placeholder) -> some View {
        ArtworkThumbnail(key: key, pixelSide: side, model: model, onFailure: { failed.insert(key) },
                         placeholder: placeholder)
    }
}
