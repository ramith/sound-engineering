import LibraryStore
import SwiftUI

// MARK: - Album grid cell (S9.4)

/// One album in the grid: 1:1 art + title + artist (no track-count — grid clutter). The hover
/// Play overlay and the Open button are owned by the enclosing `AlbumGridItem`; this view is the
/// pure content + accessibility. VoiceOver: one combined element with Play / Play Next /
/// Add-to-Queue custom actions (hover is invisible to VO; Open is the button's activation).
struct AlbumCell: View {
    let album: AlbumFacet
    let side: CGFloat

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            AlbumArtworkView(key: album.artworkKey, side: side)
            Text(album.title)
                .font(DesignSystem.Font.bodyMedium)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(2, reservesSpace: true)
            Text(album.albumArtist)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .lineLimit(1)
        }
        .frame(width: side, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play") { Task { await model.playAlbum(album.id) } }
        .accessibilityAction(named: "Play Next") { Task { await model.playAlbumNext(album.id) } }
        .accessibilityAction(named: "Add to Queue") { Task { await model.appendAlbum(album.id) } }
    }

    private var accessibilityLabel: String {
        var parts = [album.title, album.albumArtist]
        if album.year > 0 { parts.append("\(album.year)") }
        return parts.joined(separator: ", ")
    }
}
