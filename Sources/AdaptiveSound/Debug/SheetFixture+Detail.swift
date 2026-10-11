#if DEBUG
    import Foundation
    import LibraryBrowseKit
    import LibraryStore

    // MARK: - Picture-sheet fixture data: the detail pages (S10.8 E2/E3)

    extension SheetFixture {
        /// The page-states sheet's selection: the album's 2nd and 3rd songs — the anchor, and so the
        /// ring, on the 2nd.
        static let pageSelection: Set<LibraryTrackDisplay.ID> = [402, 403]

        /// Every cover key the page fixtures use.
        static let pageArtworkKeys = ["page-roja"]

        /// The album page (`SheetVariant.page`, album 10): "Roja" — the playing song's album, so its
        /// playing row shows — with a cover, the album artist, the year and eight songs, one in Tamil
        /// script.
        static func albumPage() -> LibraryDetailContent {
            let songs = albumSongs(albumID: 10, title: "Roja", year: 1992, artist: "A. R. Rahman", [
                PageSong(401, "Chinna Chinna Aasai", 1, 296), PageSong(402, "Kadhal Rojave", 2, 301),
                PageSong(403, "Pudhu Vellai Mazhai", 3, 312), PageSong(4, playingTitle, 4, 245),
                PageSong(405, "Rukkumani Rukkumani", 5, 317), PageSong(406, "Tamizha Tamizha", 6, 330),
                PageSong(407, "காதல் ரோஜாவே", 7, 301), PageSong(408, "Kadhal Rojave (Sad Version)", 8, 119),
            ])
            return LibraryDetailContent(title: "Roja", subtitle: "A. R. Rahman", year: 1992,
                                        artworkKey: "page-roja",
                                        layout: DetailTrackLayout(tracks: songs, arrangement: .album))
        }

        /// One song of a page fixture: its id, title, track number and length in seconds.
        struct PageSong {
            let id: Int64
            let title: String
            let track: Int?
            let seconds: Int64

            init(_ id: Int64, _ title: String, _ track: Int?, _ seconds: Int64) {
                self.id = id
                self.title = title
                self.track = track
                self.seconds = seconds
            }
        }

        /// One album's songs as the store reads them: disc 1, in the order given, a FLAC / M4A mix.
        private static func albumSongs(albumID: Int64, title: String, year: Int, artist: String,
                                       _ songs: [PageSong]) -> [LibraryTrackDisplay] {
            songs.map { song in
                let format = song.id % 2 == 0 ? "FLAC" : "M4A"
                return LibraryTrackDisplay(
                    id: song.id, url: URL(filePath: "/fixture/page/\(song.id).\(format.lowercased())"),
                    title: song.title, artistID: 100, artistName: artist, albumID: albumID,
                    albumName: title, format: format, trackNo: song.track,
                    durationMs: song.seconds * 1000, year: year, artworkKey: nil, dateAdded: 0,
                    sampleRate: 48000, bitDepth: format == "FLAC" ? 24 : nil, discNo: 1,
                    fileSize: song.seconds * 600_000, playCount: 0, lastPlayed: nil, albumArtistName: artist,
                    genreName: "Soundtrack"
                )
            }
        }
    }
#endif
