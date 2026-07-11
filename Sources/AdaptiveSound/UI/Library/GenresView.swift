import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Genres tab (S9.6)

/// The Genres list root. Hides 0-song genres (e.g. one orphaned by a retag) via `FacetListVisibility`;
/// opening a genre pushes `.genre(id)` → `GenreDetailView`.
struct GenresListView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        FacetListRoot(
            items: model.genres.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) },
            state: model.genresState,
            empty: FacetListEmpty(
                title: "No Genres",
                systemImage: "guitars",
                hint: "Songs without a genre tag won't appear here."
            ),
            name: \.name,
            count: \.trackCount,
            ref: { .genre($0.id) },
            route: { .genre($0.id) },
            load: { await model.loadGenres() },
            filterPlaceholder: "Filter Genres",
            noun: "genre"
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
