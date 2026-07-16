import LibraryBrowseKit
import SwiftUI

// MARK: - Shared facet list components (S9.6 — reused by Artists / Genres / Years)

/// Play / Play Next / Add to Queue for a whole facet — the list-row context menu (clone of
/// `AlbumQueueActions`, keyed on a `FacetRef` so year=Int and artist/genre=Int64 all route through
/// the model's read-then-enqueue verbs, which stay silent on an empty facet).
struct FacetQueueActions: View {
    let ref: LibraryBrowseModel.FacetRef
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        Button("Play") { Task { await model.playFacet(ref) } }
        Button("Play Next") { Task { await model.playFacetNext(ref) } }
        Button("Add to Queue") { Task { await model.appendFacet(ref) } }
        // Reference-add the whole artist/genre to a playlist; ids resolved on demand. No picker
        // overflow — a tile menu has no sheet host (S10.3).
        AddToPlaylistMenu(resolveTrackIDs: { await model.facetTrackIDs(ref) })
    }
}

/// One facet list row: the name (Artist / Genre / "2021") + a right-aligned "N songs" count.
/// Text-only — Artists/Genres/Years have no per-row artwork, and a repeated identical glyph on
/// every row is noise, not scannability (ui-designer review).
struct FacetRowLabel: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Text(name)
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(1)
            Spacer(minLength: DesignSystem.Spacing.small)
            Text(FacetCountLabel.songs(count: count))
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
        }
        .contentShape(Rectangle())
    }
}

/// The "this facet is empty while the library is not" state — distinct from `LibraryEmptyStateView`'s
/// "No Music Found", because e.g. an all-untagged library yields zero artists while songs exist.
struct FacetListEmpty: View {
    let title: String
    let systemImage: String
    let hint: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(hint)
        }
    }
}
