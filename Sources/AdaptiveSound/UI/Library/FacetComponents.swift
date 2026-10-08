import SwiftUI

// MARK: - Shared facet components (S9.6 — the browse tiles' menu, the facet empty state)

/// Play / Play Next / Add to Queue / Add to Playlist for a whole album, artist or genre — a browse
/// tile's context menu, keyed on a `FacetRef` so all three route through the model's
/// read-then-enqueue verbs, which stay silent on an empty facet.
struct FacetQueueActions: View {
    let ref: LibraryBrowseModel.FacetRef
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        Button("Play") { Task { await model.playFacet(ref) } }
        Button("Play Next") { Task { await model.playFacetNext(ref) } }
        Button("Add to Queue") { Task { await model.appendFacet(ref) } }
        // Reference-add the whole album / artist / genre to a playlist; ids resolved on demand. No
        // picker overflow — a tile menu has no sheet host (S10.3).
        AddToPlaylistMenu(resolveTrackIDs: { await model.facetTrackIDs(ref) })
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
