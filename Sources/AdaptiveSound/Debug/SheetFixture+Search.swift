#if DEBUG
    import Foundation
    import LibraryBrowseKit
    import LibraryStore

    // MARK: - Picture-sheet fixture data: the Library's Search page (R1.1-B, US-R1F-14)

    extension SheetFixture {
        /// What the search world has typed: it finds songs, albums, genres and playlists of the fixture.
        static let searchText = "ro"

        /// The search world: ⌘F's page, its results the one search rule's over the fixture library — the
        /// real `LibrarySearch`, so the sheet shows its ranking and its sections' limits.
        static func seedSearch(_ browse: LibraryBrowseModel, songs: [LibraryTrackDisplay]) {
            let playlists = [
                Playlist(id: 31, name: "Road Trip", isBuiltin: false, createdAt: 0, entryCount: 42),
                Playlist(id: 32, name: "Rock Classics", isBuiltin: false, createdAt: 0, entryCount: 120),
            ]
            let found = songs.filter { SearchRule.Query(searchText).matches([$0.title, $0.artistName,
                                                                             $0.albumName ?? ""]) }
            let lists = LibrarySearch.Lists(songs: found, albums: albums(), artists: artists(), genres: genres(),
                                            playlists: playlists)
            browse.search.seedRenderFixture(text: searchText,
                                            results: LibrarySearch.results(for: searchText, in: lists))
        }
    }
#endif
