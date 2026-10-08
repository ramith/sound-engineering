import SwiftUI

// MARK: - Cover-art thumbnail view (S9.4, design §5)

/// A fixed-size cover for rows and the album page: the shared loader (`ArtworkThumbnail`) in a
/// `side`×`side` square with `Radius.control` corners and a hairline, a ♪ on the `card` fill while
/// there is no cover. `accessibilityHidden` — the owning cell / row carries the label. (The browse
/// tiles draw their art with `BrowseArt`.)
struct AlbumArtworkView: View {
    let key: String?
    let side: CGFloat
    /// The browse model, as a plain value — see `ArtworkThumbnail.model`.
    let model: LibraryBrowseModel

    var body: some View {
        ArtworkThumbnail(key: key, pixelSide: side, model: model) {
            ZStack {
                DesignSystem.Color.card
                Image(systemName: "music.note")
                    .font(.system(size: max(14, side * 0.28)))
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: DesignSystem.Radius.control)) // also clips scaledToFill overflow
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                .strokeBorder(DesignSystem.Color.hairline, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
