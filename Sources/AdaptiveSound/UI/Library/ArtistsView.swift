import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Artists tab (S9.6)

/// The Artists list root. Hides 0-song artists (e.g. an album-artist-only "Various Artists" with no
/// track-level appearances) via the pure `FacetListVisibility` predicate; the rest is the shared
/// `FacetListRoot` scaffold. Opening an artist pushes `.artist(id)` → `ArtistDetailView`.
struct ArtistsListView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        FacetListRoot(
            items: model.artists.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) },
            state: model.artistsState,
            empty: FacetListEmpty(
                title: "No Artists",
                systemImage: "music.mic",
                hint: "Songs without artist tags won't appear here."
            ),
            name: \.name,
            count: \.trackCount,
            ref: { .artist($0.id) },
            route: { .artist($0.id) },
            load: { await model.loadArtists() }
        )
    }
}

/// One artist's songs, GROUPED by album (founder decision Q-a) — reuses `FacetTrackListView` in
/// its grouped mode. Loads the header facet + tracks into local `@State` (mirrors `AlbumDetailView`),
/// keyed on `artistID` so switching sibling artists reloads. Uses the TRACK-artist lens
/// (`tracksDisplay(byArtist:)`) — the songs this artist performs, incl. compilation appearances.
struct ArtistDetailView: View {
    let artistID: Int64

    @Environment(LibraryBrowseModel.self) private var model
    @State private var artist: ArtistFacet?
    @State private var tracks: [LibraryTrackDisplay] = []

    var body: some View {
        FacetTrackListView(
            title: artist?.name ?? "",
            backLabel: "Back to Artists",
            tracks: tracks,
            groupByAlbum: true
        )
        .task(id: artistID) {
            artist = await model.artist(id: artistID)
            tracks = await model.tracks(byArtist: artistID)
        }
    }
}
