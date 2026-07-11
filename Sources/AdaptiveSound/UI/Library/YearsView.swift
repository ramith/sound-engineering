import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Years tab (S9.6)

/// The Years list root (newest-first — `yearFacets()` is track-year DESC). No 0-song filter needed:
/// `yearFacets()` only returns years that HAVE songs. Opening a year pushes `.year(y)` → `YearDetailView`.
struct YearsListView: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        FacetListRoot(
            items: model.years,
            state: model.yearsState,
            empty: FacetListEmpty(
                title: "No Years",
                systemImage: "calendar",
                hint: "Songs without a year tag won't appear here."
            ),
            name: { String($0.year) }, // a bare year — never thousands-grouped
            count: \.trackCount,
            ref: { .year($0.year) },
            route: { .year($0.year) },
            load: { await model.loadYears() }
        )
    }
}

/// A year's songs — FLAT, with "Artist · Album" on each row's secondary line. No header facet to load
/// (the year IS the `Int` title); just the track list, keyed on `year`.
struct YearDetailView: View {
    let year: Int

    @Environment(LibraryBrowseModel.self) private var model
    @State private var tracks: [LibraryTrackDisplay] = []

    var body: some View {
        FacetTrackListView(
            title: String(year),
            backLabel: "Back to Years",
            tracks: tracks,
            groupByAlbum: false
        )
        .task(id: year) {
            tracks = await model.tracks(inYear: year)
        }
    }
}
