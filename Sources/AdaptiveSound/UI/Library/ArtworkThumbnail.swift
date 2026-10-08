import AppKit
import SwiftUI

// MARK: - Cover thumbnail loader (S9.4 design §5; split out of `AlbumArtworkView` in S10.8 D5)

/// One cover thumbnail, loaded by key through `LibraryBrowseModel` (→ `ArtworkThumbnailStore`),
/// with `placeholder` until — or unless — it decodes. It fills the frame its parent gives it and
/// overflows it (scaled to fill), so the parent frames and clips it: `AlbumArtworkView` (rows and
/// the album page) and `BrowseArt` (the browse tiles, one cover or four) share this one loader.
///
/// `.task(id: key)` cancels the in-flight decode when the view scrolls off or is reused; a
/// synchronous cache peek avoids a placeholder flash on hits; the cover fades in (Reduce Motion:
/// at once).
struct ArtworkThumbnail<Placeholder: View>: View {
    let key: String?
    /// The side, in points, to decode for (the cache holds one size per key — see the callers).
    let pixelSide: CGFloat
    /// The browse model, passed in as a plain value — NOT `@Environment`. A `Table` cell's
    /// `@Environment(Observable)` property is updated in a DETACHED graph host during the
    /// sort-driven preferences/accessibility pass, where the injected object is unresolvable →
    /// `EnvironmentValues.subscript` asserts (the header-click crash). A plain `let` has no
    /// `EnvironmentBox` to update, so it can't trap; the caller (always an env holder) passes it in.
    let model: LibraryBrowseModel
    @ViewBuilder let placeholder: Placeholder

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetArtwork.swift`): the fixture's covers.
        @Environment(\.sheetArtwork) private var sheetArtwork
    #endif

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: key) { await load() }
        .animation(reduceMotion ? nil : .easeIn(duration: 0.2), value: image != nil)
    }

    private func load() async {
        guard let key else { image = nil; return }
        #if DEBUG
            if let fixture = sheetArtwork[key] {
                image = fixture; return
            }
        #endif
        if let hit = model.cachedArtwork(forKey: key) {
            image = hit; return
        }
        image = nil
        let maxPixel = min(512, Int((pixelSide * displayScale).rounded(.up)))
        let loaded = await model.artworkImage(forKey: key, maxPixel: maxPixel)
        // The view's `key` changed mid-decode (`.task(id:)` cancelled us): don't paint a stale
        // cover over the one now in this slot (review S4). `.task(id:)` cancels synchronously on
        // the main actor, so by the time we resume here `isCancelled` already reflects the change.
        guard !Task.isCancelled else { return }
        image = loaded
    }
}
