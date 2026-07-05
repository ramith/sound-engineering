import AppKit
import SwiftUI

// MARK: - Cover-art thumbnail view (S9.4, design §5)

/// Async-loads a local cover-art thumbnail via `LibraryBrowseModel` (→ ArtworkThumbnailStore).
/// `.task(id: key)` cancels the in-flight decode when the cell scrolls off / is reused; a
/// synchronous cache peek avoids a placeholder flash on hits; the art fades in (Reduce-Motion
/// gated) and is `accessibilityHidden` (the owning cell/row carries the label).
struct AlbumArtworkView: View {
    let key: String?
    let side: CGFloat

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?

    var body: some View {
        artwork
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.control)) // also clips scaledToFill overflow
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                    .strokeBorder(DesignSystem.Color.hairline, lineWidth: 0.5)
            }
            .task(id: key) { await load() }
            .animation(reduceMotion ? nil : .easeIn(duration: 0.2), value: image != nil)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        if let image {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                DesignSystem.Color.card
                Image(systemName: "music.note")
                    .font(.system(size: max(14, side * 0.28)))
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
        }
    }

    private func load() async {
        guard let key else { image = nil; return }
        if let hit = model.cachedArtwork(forKey: key) { image = hit; return }
        image = nil
        let maxPixel = min(512, Int((side * displayScale).rounded(.up)))
        let loaded = await model.artworkImage(forKey: key, maxPixel: maxPixel)
        // The cell's `key` changed mid-decode (`.task(id:)` cancelled us): don't paint a stale
        // cover over the album now in this slot (review S4). `.task(id:)` cancels synchronously on
        // the main actor, so by the time we resume here `isCancelled` already reflects the change.
        guard !Task.isCancelled else { return }
        image = loaded
    }
}
