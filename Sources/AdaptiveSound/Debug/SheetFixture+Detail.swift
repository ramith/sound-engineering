#if DEBUG
    import Foundation
    import LibraryBrowseKit
    import LibraryStore

    // MARK: - Picture-sheet fixture data: the detail pages (S10.8 E2/E3)

    extension SheetFixture {
        /// The page-states sheet's selection: the album's 2nd and 3rd songs — the anchor, and so the
        /// ring, on the 2nd.
        static let pageSelection: Set<LibraryTrackDisplay.ID> = [402, 403]

        /// The page-states page: the album page's "Roja" as a TWO-disc album (a "Disc 1" / "Disc 2"
        /// sub-header each, track numbers starting again), one song by another artist (named after
        /// its title, decision 12's compilations), the playing row, and — from `pageSelection` — two
        /// selected rows with the keyboard ring.
        private static func albumStatesPage() -> LibraryDetailContent {
            let songs = albumSongs(albumID: 10, title: "Roja", year: 1992, artist: "A. R. Rahman", [
                PageSong(401, "Chinna Chinna Aasai", 1, 296), PageSong(402, "Kadhal Rojave", 2, 301),
                PageSong(403, "Pudhu Vellai Mazhai", 3, 312), PageSong(4, playingTitle, 4, 245),
                PageSong(405, "Rukkumani Rukkumani", 5, 317), PageSong(406, "Tamizha Tamizha", 1, 330, disc: 2),
                PageSong(407, "காதல் ரோஜாவே", 2, 301, disc: 2, artist: "S. P. Balasubrahmanyam"),
                PageSong(408, "Kadhal Rojave (Sad Version)", 3, 119, disc: 2),
            ])
            return LibraryDetailContent(title: "Roja", subtitle: "A. R. Rahman", year: 1992,
                                        artworkKey: "page-roja",
                                        layout: DetailTrackLayout(tracks: songs, arrangement: .album))
        }

        /// Every cover key the page fixtures use.
        static let pageArtworkKeys = ["page-roja"]

        /// The album page (`SheetVariant.page`, album 10): "Roja" — the playing song's album, so its
        /// playing row shows — with a cover, the album artist, the year and eight songs, one in Tamil
        /// script.
        private static func albumPage() -> LibraryDetailContent {
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

        /// The world's page (`SheetVariant.page`): album 10 (its states version for `pageStates`),
        /// artist 1, or genre 23; nil for a world that opens none.
        static func detailPage(for variant: SheetVariant) -> LibraryDetailContent? {
            if variant == .pageStates {
                return albumStatesPage()
            }
            return switch variant.page {
            case .album: albumPage()
            case .artist: artistPage()
            case .genre: genrePage()
            case nil: nil
            }
        }

        /// The artist page: "A. R. Rahman" (artist 1) under its tile's cover (decision 35), four albums
        /// in the store's album order, each under its header with its year — the playing song in
        /// "Roja", Tamil script and a long album title. The songs arrive in TITLE order, so the sheet
        /// shows the page's own order: "Rockstar" and "Slumdog Millionaire" by track (3, 7, 9 and 2,
        /// 14), and Bombay's song with no track number last, its number blank.
        private static func artistPage() -> LibraryDetailContent {
            let artist = "A. R. Rahman"
            let songs = albumSongs(albumID: 4, title: "Bombay", year: 1995, artist: artist, [
                PageSong(502, "Hamma Hamma", 4, 333), PageSong(503, "Kehna Hi Kya", nil, 352),
                PageSong(2, "கண்ணாளனே", 3, 357),
            ]) + albumSongs(albumID: 9, title: "Rockstar", year: 2011, artist: artist, [
                PageSong(3, "Kun Faya Kun", 7, 473), PageSong(504, "Nadaan Parindey", 9, 380),
                PageSong(505, "Sadda Haq", 3, 375),
            ]) + albumSongs(albumID: 10, title: "Roja", year: 1992, artist: artist, [
                PageSong(401, "Chinna Chinna Aasai", 1, 296), PageSong(4, playingTitle, 4, 245),
            ]) + albumSongs(albumID: 11, title: "Slumdog Millionaire (Music from the Motion Picture)", year: 2008,
                            artist: artist, [PageSong(5, "Jai Ho", 14, 319), PageSong(509, "O... Saya", 2, 214)])
            // The cover of its tile in the Artists grid (`artists()`: artist 1 shows album 4's).
            return LibraryDetailContent(title: artist, subtitle: nil, year: nil, artworkKey: "album-4",
                                        layout: DetailTrackLayout(tracks: songs, arrangement: .byAlbum))
        }

        /// The genre page: "Soundtrack" (genre 23, whose tile is a full mosaic), one flat list of many
        /// artists' songs, each with "Artist · Album" — the playing song among them, a long title, a
        /// song with no artist or album, and accented names.
        private static func genrePage() -> LibraryDetailContent {
            let songs = albumSongs(albumID: 9, title: "Rockstar", year: 2011, artist: "A. R. Rahman", [
                PageSong(3, "Kun Faya Kun", 7, 473),
            ]) + albumSongs(albumID: 10, title: "Roja", year: 1992, artist: "A. R. Rahman", [
                PageSong(4, playingTitle, 4, 245),
            ]) + albumSongs(albumID: 11, title: "Slumdog Millionaire", year: 2008, artist: "A. R. Rahman", [
                PageSong(5, "Jai Ho", 14, 319),
            ]) + albumSongs(albumID: 21, title: "Amélie", year: 2001, artist: "Yann Tiersen", [
                PageSong(611, "Comptine d’un autre été, l’après-midi", 5, 140),
            ]) + albumSongs(albumID: 22, title: "Inception", year: 2010, artist: "Hans Zimmer", [
                PageSong(612, "Time", 12, 275),
            ]) + albumSongs(albumID: 23, title: "Interstellar", year: 2014, artist: "Hans Zimmer", [
                PageSong(613, "Cornfield Chase", 2, 126),
            ]) + albumSongs(albumID: 24, title: "The Good, the Bad and the Ugly", year: 1966,
                            artist: "Ennio Morricone", [
                                PageSong(614, "The Ecstasy of Gold (From “The Good, the Bad and the Ugly”) — "
                                    + "Remastered 2004 Version, Original Motion Picture Soundtrack", 11, 202),
                            ]) + [unknownSong]
            return LibraryDetailContent(title: "Soundtrack", subtitle: nil, year: nil, artworkKey: nil,
                                        layout: DetailTrackLayout(tracks: songs, arrangement: .flat))
        }

        /// A song with no artist and no album, as the store projects one ("" artist, nil album).
        private static var unknownSong: LibraryTrackDisplay {
            LibraryTrackDisplay(
                id: 615, url: URL(filePath: "/fixture/page/615.flac"), title: "Untitled Field Recording 07",
                artistID: nil, artistName: "", albumID: nil, albumName: nil, format: "FLAC", trackNo: nil,
                durationMs: 188_000, year: nil, artworkKey: nil, dateAdded: 0, sampleRate: 96000, bitDepth: 24,
                discNo: nil, fileSize: 90_000_000, playCount: 0, lastPlayed: nil, albumArtistName: nil,
                genreName: "Soundtrack"
            )
        }

        /// One song of a page fixture: its id, title, track number and length in seconds — on disc 1
        /// and by its album's artist unless told otherwise.
        struct PageSong {
            let id: Int64
            let title: String
            let track: Int?
            let seconds: Int64
            let disc: Int
            let artist: String?

            init(_ id: Int64, _ title: String, _ track: Int?, _ seconds: Int64, disc: Int = 1,
                 artist: String? = nil) {
                self.id = id
                self.title = title
                self.track = track
                self.seconds = seconds
                self.disc = disc
                self.artist = artist
            }
        }

        /// One album's songs as the store reads them: in the order given, a FLAC / M4A mix.
        private static func albumSongs(albumID: Int64, title: String, year: Int, artist: String,
                                       _ songs: [PageSong]) -> [LibraryTrackDisplay] {
            songs.map { song in
                let format = song.id % 2 == 0 ? "FLAC" : "M4A"
                return LibraryTrackDisplay(
                    id: song.id, url: URL(filePath: "/fixture/page/\(song.id).\(format.lowercased())"),
                    title: song.title, artistID: 100, artistName: song.artist ?? artist, albumID: albumID,
                    albumName: title, format: format, trackNo: song.track,
                    durationMs: song.seconds * 1000, year: year, artworkKey: nil, dateAdded: 0,
                    sampleRate: 48000, bitDepth: format == "FLAC" ? 24 : nil, discNo: song.disc,
                    fileSize: song.seconds * 600_000, playCount: 0, lastPlayed: nil, albumArtistName: artist,
                    genreName: "Soundtrack"
                )
            }
        }
    }
#endif
