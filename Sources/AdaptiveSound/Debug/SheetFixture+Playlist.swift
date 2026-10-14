#if DEBUG
    import LibraryScan
    import LibraryStore

    // MARK: - Picture-sheet fixture data: the playlist page (S10.8 E4)

    extension SheetFixture {
        /// The open playlist: a name long enough to share the header's line with its pills, so it
        /// truncates at the 880×640 minimum.
        static let openPlaylist = Playlist(id: 1, name: "Late-night drive, windows down", isBuiltin: false,
                                           createdAt: 0, entryCount: playlistTitles.count)

        /// The failure notice's reason: Locate onto a file another track already owns.
        static let playlistFailure = "That file is already in your library under a different track."

        /// The open playlist's songs, in the listener's order: the long title, non-Latin scripts, one whose
        /// file is gone (with an artist) and one out of reach on a drive that isn't connected (untagged).
        private static let playlistTitles = [
            "Clair de Lune", "Teardrop", playingTitle, longTitle, "Hallelujah", "夜に駆ける", "Nuvole Bianche",
            "Untitled Field Recording 03", "So What", "Svefn-g-englar", "கண்ணாளனே", "Archangel",
        ]

        /// The songs that can't be played, and why.
        private static let unavailableTitles: [String: FileAvailability] = [
            "Hallelujah": .missing, "Untitled Field Recording 03": .unreachable,
        ]

        /// Opens the playlist worlds' playlist: the rail lists it with two more, and the card shows it,
        /// through the models' own seeds (no store).
        static func seedPlaylist(_ playlists: PlaylistsModel, browse: LibraryBrowseModel,
                                 songs: [LibraryTrackDisplay]) {
            let byTitle = Dictionary(uniqueKeysWithValues: songs.map { ($0.title, $0) })
            let rows = playlistTitles.enumerated().compactMap { position, title -> PlaylistDetailEntry? in
                guard let song = byTitle[title] else { return nil }
                let entry = PlaylistEntry(id: 1000 + Int64(position), playlistID: openPlaylist.id, trackID: song.id,
                                          position: position, addedAt: 0)
                return PlaylistDetailEntry(entry: entry, display: song,
                                           availability: unavailableTitles[title] ?? .available)
            }
            let tree = [
                openPlaylist,
                Playlist(id: 2, name: "Focus", isBuiltin: false, createdAt: 0, entryCount: 48),
                Playlist(id: 3, name: "Sunday morning", isBuiltin: false, createdAt: 0, entryCount: 23),
            ]
            playlists.seedRenderFixture(playlists: tree, open: openPlaylist.id, rows: rows)
            browse.selectPlaylist(openPlaylist.id)
        }
    }
#endif
