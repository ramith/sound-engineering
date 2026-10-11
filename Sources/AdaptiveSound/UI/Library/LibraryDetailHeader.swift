import SwiftUI

// MARK: - Detail page header (S10.8 E2/E3 — the album, artist and genre pages)

/// The header of an album, artist or genre page, in the Library card's header grammar (Sprint D's
/// `LibraryCardHeader`): the back pill (⌘[) above the page's art, title, subtitle and mono count
/// line, its actions under them, and a hairline inset with the text. The art is the page's tile art
/// (`BrowseArt`) — an album's cover, a genre's mosaic — so the page reads as opened from that tile.
struct LibraryDetailHeader: View {
    let ref: LibraryBrowseModel.FacetRef
    let content: LibraryDetailContent
    /// "Add to Playlist…": the page's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    @Environment(LibraryBrowseModel.self) private var model

    /// The cover's side — the album page's shipped size.
    private static let artSide: CGFloat = 148

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HeaderPillButton(ref.category.title, systemImage: "chevron.backward",
                                 help: "Back to \(ref.category.title)", action: goBack)
                    .keyboardShortcut("[", modifiers: .command)
                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    if let artworkKeys {
                        BrowseArt(keys: artworkKeys, side: Self.artSide,
                                  placeholderSymbol: ref.category.tilePlaceholderSymbol, model: model)
                            .frame(width: Self.artSide)
                    }
                    titles
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 14)
            .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
            Rectangle()
                .fill(DesignSystem.Color.hairline)
                .frame(height: 1)
                .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        }
    }

    /// Title, subtitle and count line, with the page's actions under them.
    private var titles: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
            Text(content.title)
                .font(DesignSystem.Font.displayTitle)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(2)
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(DesignSystem.Font.sectionTitle)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .lineLimit(1)
            }
            Text(content.countLine)
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .lineLimit(1)
            // Shuffle where the page had it: an artist's or a genre's, not an album's.
            LibraryDetailActions(rows: content.layout.rows, offersShuffle: ref.category != .albums,
                                 choosePlaylist: choosePlaylist)
                .padding(.top, DesignSystem.Spacing.small)
        }
    }

    /// The page's art, as on its tile: an album's cover; a genre's 2×2 mosaic of its biggest albums'
    /// covers (decision 34 — the Genres grid's own cover read, live, so it follows a library change);
    /// the placeholder without any. An artist's page has none (nil), as before.
    private var artworkKeys: [String]? {
        switch ref {
        case .album: content.artworkKey.map { [$0] } ?? []
        case .artist: nil
        case let .genre(id): model.genreCoverKeys[id] ?? []
        }
    }

    /// Back to the grid the page was opened from (it comes back where it was, D6). Guarded:
    /// `removeLast()` on an empty path traps.
    private func goBack() {
        if !model.path.isEmpty {
            model.path.removeLast()
        }
    }
}
