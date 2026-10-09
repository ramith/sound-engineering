import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Genres tab (S9.6; on the browse grid since S10.8 D5, decision 19)

/// The Genres root: the shared browse scaffold and tile (`BrowseGridRoot` → `BrowseGrid`), like
/// Albums and Artists. A genre's art is a 2×2 mosaic of its biggest albums' covers (one cover with
/// one to three, the guitars glyph with none — `CoverArrangement`), from the cover read that loads
/// with the genres (`loadGenres`, paths already warmed); its subtitle is "N songs". Hides 0-song
/// genres (e.g. one orphaned by a retag) via `FacetListVisibility`; opening a genre pushes
/// `.genre(id)` → `GenreDetailView`.
struct GenresListView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        // Read here, not inside the tile closure, so new covers re-render this root and its tiles.
        let covers = model.genreCoverKeys
        BrowseGridRoot(
            category: .genres,
            items: model.genres.filter { FacetListVisibility.isVisible(trackCount: $0.trackCount) },
            state: model.genresState,
            noun: "genre",
            // Songs may exist but be untagged — NOT the "No Music Found" library-empty state.
            empty: FacetListEmpty(
                title: "No Genres",
                systemImage: "guitars",
                hint: "Songs without a genre tag won't appear here."
            ),
            filterKeys: { [$0.name] },
            title: \.name,
            load: { await model.loadGenres() },
            tile: { genre in
                BrowseTileContent(ref: .genre(genre.id), title: genre.name,
                                  subtitle: FacetCountLabel.songs(count: genre.trackCount),
                                  artworkKeys: covers[genre.id] ?? [])
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
