import SwiftUI

// MARK: - Browse tile (S10.8 D5 — the one tile of Albums, Artists and Genres)

/// One tile of a browse grid: the art (`BrowseArt`), the title and the subtitle, one line each, on
/// a plate. The whole tile is an Open button; its plate, hit area and keyboard ring live INSIDE the
/// button's label, so what highlights is what clicks. States, one rule with the Songs rows: at rest
/// no plate; hovered, the `controlHover` plate and the Play button; the keyboard cursor, the A3
/// ring on the plate (keyboard mode only — the grid switches the system focus effect off).
///
/// The hover Play button is a SIBLING overlay ABOVE the Open button — not nested in its label — so
/// it reliably wins the hit test on macOS (review §6); it sits at the art's bottom-trailing corner
/// and is hidden from VoiceOver, which gets Play / Play Next / Add to Queue as the tile's actions.
/// The Open button is no focus stop of its own: the grid is ONE stop whose arrow keys move the ring
/// (decision 20). The context menu carries the queue verbs and Add to Playlist.
struct BrowseTile: View {
    let content: BrowseTileContent
    /// The art's laid-out side (sizes its glyphs and the cover decode); the tile fills its column.
    let artSide: CGFloat
    let placeholderSymbol: String
    /// The grid holds key focus and this is the tile its keys act on (the ring is drawn).
    let isKeyboardCursor: Bool
    let open: () -> Void

    @Environment(LibraryBrowseModel.self) private var model
    @State private var hovering = false
    #if DEBUG
        /// Picture-sheet renderer only (`Debug/SheetFixture.swift`): the tile it draws hovered.
        @Environment(\.sheetGridStates) private var sheetGridStates
    #endif

    private typealias Metrics = DesignSystem.BrowseGrid

    var body: some View {
        Button(action: open) {
            plate
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("\(content.title)\n\(content.subtitle)")
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityAction(named: "Play", play)
        .accessibilityAction(named: "Play Next", playNext)
        .accessibilityAction(named: "Add to Queue", append)
        .overlay(alignment: .top) {
            if hovering {
                playButtonSlot
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { FacetQueueActions(ref: content.ref) }
        #if DEBUG
            .onAppear {
                if sheetGridStates.hovered == content.ref {
                    hovering = true
                }
            }
        #endif
    }

    /// The tile's face: art, then title and subtitle, on the plate.
    private var plate: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrowseArt(keys: content.artworkKeys, side: artSide, placeholderSymbol: placeholderSymbol, model: model)
            Text(content.title)
                .font(DesignSystem.Font.bodyMedium)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(1)
                .padding(.top, Metrics.titleGap)
            Text(content.subtitle)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .lineLimit(1)
                .padding(.top, Metrics.subtitleGap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.platePadding)
        .background(hovering ? DesignSystem.Color.controlHover : .clear,
                    in: RoundedRectangle(cornerRadius: Metrics.plateRadius))
        .keyboardCursorRing(isKeyboardCursor, cornerRadius: Metrics.plateRadius)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.plateRadius))
    }

    /// The art's square (inside the plate's padding) with Play at its bottom-trailing corner. The
    /// clear square takes no clicks: outside the button, the click opens the tile.
    private var playButtonSlot: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomTrailing) {
                Button("Play", systemImage: "play.circle.fill", action: play)
                    .labelStyle(.iconOnly)
                    .font(.system(size: max(Metrics.playGlyphMinimum, artSide * Metrics.playGlyphScale)))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(DesignSystem.Color.onAccent, DesignSystem.Color.accentFill)
                    .shadow(radius: 3)
                    .buttonStyle(.plain)
                    .help("Play")
                    .padding(DesignSystem.Spacing.small)
                    .accessibilityHidden(true) // the tile exposes Play as an action
            }
            .padding(Metrics.platePadding)
    }

    private func play() {
        Task { await model.playFacet(content.ref) }
    }

    private func playNext() {
        Task { await model.playFacetNext(content.ref) }
    }

    private func append() {
        Task { await model.appendFacet(content.ref) }
    }
}
