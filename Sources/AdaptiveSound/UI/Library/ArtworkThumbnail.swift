import AppKit
import SwiftUI

// MARK: - Cover thumbnail loader (S9.4 design §5; split out of `AlbumArtworkView` in S10.8 D5)

/// One cover thumbnail, loaded by key through `LibraryBrowseModel` (→ `ArtworkThumbnailStore`),
/// with `placeholder` until — or unless — it shows. It fills the frame its parent gives it and
/// overflows it (scaled to fill), so the parent frames and clips it: `AlbumArtworkView` (rows and
/// the album page) and `BrowseArt` (the browse tiles, one cover or four) share this one loader.
///
/// Its phase is empty (loading, or no key), success, or failure (the key has no cache row, or
/// the file is missing or undecodable) — reported once through `onFailure`, so `BrowseArt` can
/// drop a cover that will never show. A cover already in the cache shows from the FIRST frame (the
/// phase is seeded in `init`, no placeholder flash); a cached copy smaller than this slot shows at
/// once as an interim image while the store decodes a sharper one (its upgrade-only cache).
/// `.task(id: key)` cancels the in-flight decode when the view scrolls off or is reused; a cover
/// that arrives later fades in (Reduce Motion: at once).
struct ArtworkThumbnail<Placeholder: View>: View {
    /// Where the cover stands. Success and failure carry their key, so a reused view never shows
    /// the last key's cover — or its failure — for a new one.
    private enum Phase {
        case empty
        case success(key: String, image: NSImage)
        case failure(key: String)
    }

    let key: String?
    /// The side, in points, to decode for.
    let pixelSide: CGFloat
    /// The browse model, passed in as a plain value — NOT `@Environment`. A `Table` cell's
    /// `@Environment(Observable)` property is updated in a DETACHED graph host during the
    /// sort-driven preferences/accessibility pass, where the injected object is unresolvable →
    /// `EnvironmentValues.subscript` asserts (the header-click crash). A plain `let` has no
    /// `EnvironmentBox` to update, so it can't trap; the caller (always an env holder) passes it in.
    let model: LibraryBrowseModel
    /// Runs once when the cover can't be shown (no cache row, or the file is gone or undecodable).
    let onFailure: () -> Void
    let placeholder: Placeholder

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetArtwork.swift`): the fixture's covers.
        @Environment(\.sheetArtwork) private var sheetArtwork
    #endif

    init(key: String?, pixelSide: CGFloat, model: LibraryBrowseModel, onFailure: @escaping () -> Void = {},
         @ViewBuilder placeholder: () -> Placeholder) {
        self.key = key
        self.pixelSide = pixelSide
        self.model = model
        self.onFailure = onFailure
        self.placeholder = placeholder()
        // A cached cover shows from the first frame — the `.task` below runs after it is drawn.
        _phase = State(initialValue: Self.cachedPhase(for: key, in: model))
    }

    var body: some View {
        ZStack {
            if let image = shownImage {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: key) { await load() }
        .animation(reduceMotion ? nil : .easeIn(duration: 0.2), value: shownImage != nil)
    }

    /// The cover on screen: the phase's, while it belongs to the current key.
    private var shownImage: NSImage? {
        if case let .success(shownKey, image) = phase, shownKey == key {
            return image
        }
        return nil
    }

    /// The phase a cover starts in: the cached image (whatever its size), else empty.
    private static func cachedPhase(for key: String?, in model: LibraryBrowseModel) -> Phase {
        guard let key, let image = model.cachedArtwork(forKey: key) else { return .empty }
        return .success(key: key, image: image)
    }

    private func load() async {
        guard let key else { phase = .empty; return }
        #if DEBUG
            if let fixture = sheetArtwork[key] {
                phase = .success(key: key, image: fixture); return
            }
        #endif
        if shownImage == nil {
            phase = Self.cachedPhase(for: key, in: model) // a reused view: the new key's cached copy
        }
        let maxPixel = min(512, Int((pixelSide * displayScale).rounded(.up)))
        let loaded = await model.artworkImage(forKey: key, maxPixel: maxPixel)
        // The view's `key` changed mid-decode (`.task(id:)` cancelled us): don't paint a stale
        // cover over the one now in this slot (review S4). `.task(id:)` cancels synchronously on
        // the main actor, so by the time we resume here `isCancelled` already reflects the change.
        guard !Task.isCancelled else { return }
        if let loaded {
            phase = .success(key: key, image: loaded)
        } else if shownImage == nil {
            phase = .failure(key: key)
            onFailure()
        }
    }
}
