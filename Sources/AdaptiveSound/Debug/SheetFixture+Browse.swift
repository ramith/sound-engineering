#if DEBUG
    import Foundation
    import LibraryStore

    // MARK: - Picture-sheet fixture data: the browse grids (S10.8 D5)

    extension SheetFixture {
        /// The Albums grid, in its title order: the Songs fixture's albums — a long title, non-Latin
        /// and accented names, and three with no cover (the placeholder).
        static func albums() -> [AlbumFacet] {
            [
                album(1, "Ágætis byrjun", "Sigur Rós", 1999),
                album(2, "Amnesiac", "Radiohead", 2001),
                album(3, "Beethoven: Symphony No. 9 in D minor, Op. 125 “Choral”",
                      "Berliner Philharmoniker, Herbert von Karajan", 1963),
                album(4, "Bombay", "A. R. Rahman", 1995),
                album(5, "For Lack of a Better Name", "deadmau5", 2009, art: false),
                album(6, "Grace", "Jeff Buckley", 1994),
                album(7, "Kind of Blue", "Miles Davis", 1959),
                album(8, "Mezzanine", "Massive Attack", 1998),
                album(9, "Rockstar", "A. R. Rahman", 2011),
                album(10, "Roja", "A. R. Rahman", 1992, art: false),
                album(11, "Slumdog Millionaire", "A. R. Rahman", 2008),
                album(12, "Suite bergamasque", "Claude Debussy", 1905, art: false),
                album(13, "THE BOOK", "YOASOBI", 2021),
                album(14, "Una Mattina", "Ludovico Einaudi", 2004),
                album(15, "Untrue", "Burial", 2007),
                album(16, "Windowlicker", "Aphex Twin", 1999),
            ]
        }

        /// The Artists grid, by name: each with one of its albums' covers, or none — Greek and an
        /// emoji among the names.
        static func artists() -> [ArtistFacet] {
            [
                artist(1, "A. R. Rahman", songs: 4, art: 4), artist(2, "Aphex Twin", art: 16),
                artist(3, "Berliner Philharmoniker, Herbert von Karajan", art: 3), artist(4, "Burial", art: 15),
                artist(5, "Claude Debussy"), artist(6, "deadmau5"), artist(7, "Jeff Buckley", art: 6),
                artist(8, "Ludovico Einaudi", art: 14), artist(9, "Massive Attack", art: 8),
                artist(10, "Miles Davis", art: 7), artist(11, "Radiohead", art: 2), artist(12, "Sigur Rós", art: 1),
                artist(13, "YOASOBI", art: 13), artist(14, "Ελένη Καραΐνδρου", songs: 12),
                artist(15, "Ludwig van Beethoven 🎻", songs: 9, art: 3),
            ]
        }

        /// The Genres grid, by name, each with how many covers it has: most a full mosaic, some one
        /// to three (one cover), a few none (the placeholder) — a library with patchy art.
        private static let genreSpec: [(genre: GenreFacet, covers: Int)] = [
            ("Ambient", 590, 4), ("Blues", 315, 0), ("Bossa Nova", 340, 2), ("Classical", 449, 4),
            ("Country", 432, 4), ("Electronic", 500, 0), ("Folk", 465, 1), ("Funk", 281, 4),
            ("Hip-Hop", 344, 4), ("House", 546, 3), ("Indie", 532, 4), ("J-Pop", 312, 1),
            ("Jazz", 482, 4), ("K-Pop", 530, 4), ("Latin", 279, 4), ("Metal", 531, 4),
            ("Pop", 463, 4), ("Punk", 445, 4), ("R&B", 376, 4), ("Reggae", 378, 4),
            ("Rock", 610, 4), ("Soul", 402, 4), ("Soundtrack", 233, 4), ("Spoken Word", 12, 0),
            ("Techno", 388, 4), ("Trip-Hop", 150, 2), ("World", 96, 4),
        ].enumerated().map { index, spec in
            (GenreFacet(id: Int64(index + 1), name: spec.0, trackCount: spec.1), spec.2)
        }

        static func genres() -> [GenreFacet] {
            genreSpec.map(\.genre)
        }

        /// Each genre's covers (the store's `genreCoverArtworkKeys` shape): only genres with any.
        static func genreCovers() -> [Int64: [String]] {
            var covers: [Int64: [String]] = [:]
            for (genre, count) in genreSpec where count > 0 {
                covers[genre.id] = (1 ... count).map { "genre-\(genre.id)-\($0)" }
            }
            return covers
        }

        /// The states sheet (`SheetVariant.gridStates`): Blues hovered — a placeholder tile, so the
        /// plate shows against the wash — and the keyboard ring on Bossa Nova.
        static let gridStates = SheetGridStates(hovered: .genre(2), cursor: .genre(3))

        /// Every cover key the browse fixtures use.
        static func browseArtworkKeys() -> [String] {
            albums().compactMap(\.artworkKey) + genreCovers().values.flatMap(\.self)
        }

        /// An album whose cover key, when it has one, is `album-<id>`.
        private static func album(_ id: Int64, _ title: String, _ artist: String, _ year: Int,
                                  art: Bool = true) -> AlbumFacet {
            AlbumFacet(id: id, title: title, albumArtistID: 100 + id, albumArtist: artist, year: year,
                       trackCount: 1 + Int(id) % 4, artworkKey: art ? "album-\(id)" : nil)
        }

        /// An artist showing album `art`'s cover, or none.
        private static func artist(_ id: Int64, _ name: String, songs: Int = 1, art: Int64? = nil) -> ArtistFacet {
            ArtistFacet(id: id, name: name, trackCount: songs, artworkKey: art.map { "album-\($0)" })
        }
    }
#endif
