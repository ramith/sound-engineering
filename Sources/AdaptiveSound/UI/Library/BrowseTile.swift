import SwiftUI

// MARK: - Browse tile (S10.8 — the one tile structure of the browse grids)

/// One tile of a browse grid (Albums, Artists): the whole cell is an Open button, a hover Play
/// button sits over the art, the context menu carries the queue verbs, and the keyboard ring marks
/// the cursor. Structure only — the section supplies the cell's content (`AlbumCell`,
/// `ArtistCell`); Sprint D restyles this one tile for all three grids.
///
/// The hover Play button is a SIBLING overlay ABOVE the Open button — not nested in its label — so
/// it reliably wins the hit test on macOS (review §6); it is positioned over the art (the top
/// `side`×`side` region) and is `accessibilityHidden`, because the cell exposes Play as a custom
/// action. The Open button is no focus stop of its own: the grid is ONE stop whose arrow keys move
/// the ring (decision 20), instead of a Tab stop per tile under Full Keyboard Access.
struct BrowseTile<Cell: View, Actions: View>: View {
    let side: CGFloat
    /// The grid holds key focus and this is the tile its keys act on (the ring is drawn).
    let isKeyboardCursor: Bool
    let open: () -> Void
    let play: @MainActor () async -> Void
    @ViewBuilder let cell: Cell
    @ViewBuilder let actions: Actions

    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            cell
        }
        .buttonStyle(.plain)
        .focusable(false)
        .overlay(alignment: .topLeading) {
            if hovering {
                playButton
                    .padding(DesignSystem.Spacing.small)
                    .frame(width: side, height: side, alignment: .bottomTrailing)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { actions }
        // Outside the tile — there is no tile plate to draw it on yet (Sprint D adds one).
        .overlay {
            Color.clear
                .padding(-BrowseGridMetrics.ringOutset)
                .keyboardCursorRing(isKeyboardCursor, cornerRadius: BrowseGridMetrics.ringCornerRadius)
        }
    }

    private var playButton: some View {
        Button {
            Task { await play() }
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.system(size: max(20, side * 0.26)))
                .symbolRenderingMode(.palette)
                .foregroundStyle(DesignSystem.Color.onAccent, DesignSystem.Color.accentFill)
                .shadow(radius: 3)
        }
        .buttonStyle(.plain)
        .help("Play")
        .accessibilityHidden(true) // the cell exposes Play as a custom action
    }
}
