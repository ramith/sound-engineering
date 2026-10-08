import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Genres tab (S9.6)

/// The Genres root: the shared browse scaffold over a text list (`FacetList`) until Sprint D puts
/// Genres on the browse grid (decision 19). Hides 0-song genres (e.g. one orphaned by a retag) via
/// `FacetListVisibility`; opening a genre pushes `.genre(id)` → `GenreDetailView`.
struct GenresListView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        BrowseGridRoot(
            items: model.genres.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) },
            state: model.genresState,
            // Songs may exist but be untagged — NOT the "No Music Found" library-empty state.
            empty: FacetListEmpty(
                title: "No Genres",
                systemImage: "guitars",
                hint: "Songs without a genre tag won't appear here."
            ),
            noun: "genre",
            filterPlaceholder: "Filter Genres",
            filterKeys: { [$0.name] },
            load: { await model.loadGenres() },
            content: { genres in
                FacetList(
                    items: genres,
                    name: \.name,
                    count: \.trackCount,
                    ref: { .genre($0.id) },
                    route: { .genre($0.id) }
                )
            }
        )
    }
}

/// A genre's songs — FLAT (founder Q-a: only Artists group by album), with "Artist · Album" on each
/// row's secondary line. Loads its header facet + tracks into local `@State`, keyed on `genreID`.
struct GenreDetailView: View {
    let genreID: Int64

    @Environment(LibraryBrowseModel.self) private var model
    @State private var genre: GenreFacet?
    @State private var tracks: [LibraryTrackDisplay] = []

    var body: some View {
        FacetTrackListView(
            title: genre?.name ?? "",
            backLabel: "Back to Genres",
            tracks: tracks,
            groupByAlbum: false
        )
        .task(id: genreID) {
            genre = await model.genre(id: genreID)
            tracks = await model.tracks(inGenre: genreID)
        }
    }
}
