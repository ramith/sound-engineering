#if DEBUG
    import Foundation
    import LibraryStore

    // MARK: - Picture-sheet fixture data

    extension SheetFixture {
        static let playingTitle = "Roja Jaaneman"
        static let selectedTitle = "Windowlicker"
        static let longTitle = "Symphony No. 9 in D minor, Op. 125 “Choral”: IV. Presto — Allegro assai — "
            + "Alla marcia — Andante maestoso — Allegro energico, sempre ben marcato"

        /// The play queue, in the listener's order: the playing track third, then a long title, a track
        /// with no artist, and non-Latin scripts.
        static let queueTitles = [
            "Kun Faya Kun", "Jai Ho", playingTitle, longTitle, "Untitled Field Recording 03", "夜に駆ける",
            "கண்ணாளனே", "Clair de Lune", "So What",
        ]

        /// The library, in the Songs list's default composite order (artist → album → track): a track
        /// with no artist first, the playing row 4th, the selected row 6th, the long title 7th — all
        /// on screen at the 880×640 minimum.
        static func songs() -> [LibraryTrackDisplay] {
            [
                song(1, "Untitled Field Recording 03", artist: "", album: nil, seconds: 192),
                song(2, "கண்ணாளனே", artist: "A. R. Rahman", album: "Bombay", seconds: 357),
                song(3, "Kun Faya Kun", artist: "A. R. Rahman", album: "Rockstar", seconds: 473),
                song(4, playingTitle, artist: "A. R. Rahman", album: "Roja", seconds: 245),
                song(5, "Jai Ho", artist: "A. R. Rahman", album: "Slumdog Millionaire", seconds: 319),
                song(6, selectedTitle, artist: "Aphex Twin", album: "Windowlicker", seconds: 366),
                song(7, longTitle, artist: "Berliner Philharmoniker, Herbert von Karajan",
                     album: "Beethoven: Symphony No. 9", seconds: 1468),
                song(8, "Archangel", artist: "Burial", album: "Untrue", seconds: 238),
                song(9, "Clair de Lune", artist: "Claude Debussy", album: "Suite bergamasque", seconds: 302),
                song(10, "Strobe", artist: "deadmau5", album: "For Lack of a Better Name", seconds: 637),
                song(11, "Hallelujah", artist: "Jeff Buckley", album: "Grace", seconds: 413),
                song(12, "Nuvole Bianche", artist: "Ludovico Einaudi", album: "Una Mattina", seconds: 357),
                song(13, "Teardrop", artist: "Massive Attack", album: "Mezzanine", seconds: 330),
                song(14, "So What", artist: "Miles Davis", album: "Kind of Blue", seconds: 562),
                song(15, "Pyramid Song", artist: "Radiohead", album: "Amnesiac", seconds: 289),
                song(16, "Svefn-g-englar", artist: "Sigur Rós", album: "Ágætis byrjun", seconds: 604),
                song(17, "夜に駆ける", artist: "YOASOBI", album: "THE BOOK", seconds: 261),
            ]
        }

        /// A hand-drawn 31-band curve (dB, half-dB steps): low shelf up, presence dip, air lift.
        static func eqCurve() -> [Float] {
            (0 ..< 31).map { band in
                let x = Float(band)
                let lowShelf = 6 * bump(x, at: 3, width: 3)
                let presenceDip = -4 * bump(x, at: 17, width: 3)
                let air = 3.5 * bump(x, at: 27, width: 2.5)
                return ((lowShelf + presenceDip + air) * 2).rounded() / 2
            }
        }

        /// One analyzer frame in 0...1 (`count` bars): a low-mid hump, an upper-mid shoulder, and ripple
        /// whose `phase` tells channels apart.
        static func spectrum(count: Int, phase: Float) -> [Float] {
            (0 ..< count).map { index in
                let x = Float(index) / Float(max(count - 1, 1))
                let body = 0.85 * bump(x, at: 0.18, width: 0.22) + 0.35 * bump(x, at: 0.6, width: 0.15)
                let ripple = 0.1 * sin(Float(index) * 0.9 + phase)
                return min(1, max(0.05, body - ripple))
            }
        }

        /// Stereo before/after monitor bands: "after" is "before" lifted by the EQ curve over the
        /// analyzer's dB range, so the two traces differ the way the real Monitoring tab shows.
        static func monitorSpectra() -> (before: [[Float]], after: [[Float]]) {
            let count = SpectrumConstants.bandCount
            let curve = eqCurve()
            let displayRangeDb = -SpectrumConstants.noiseFloorDB // 0...1 spans noise floor → 0 dB
            let before = [0, 1.7].map { spectrum(count: count, phase: $0) }
            let after = before.map { channel in
                channel.indices.map { index in
                    let band = Int((Float(index) / Float(count - 1) * Float(curve.count - 1)).rounded())
                    return min(1, max(0, channel[index] + curve[band] / displayRangeDb))
                }
            }
            return (before, after)
        }

        private static func bump(_ x: Float, at center: Float, width: Float) -> Float {
            exp(-pow((x - center) / width, 2))
        }

        /// A library row as the store projects it: "" artist when untagged (COALESCE), nil album when
        /// absent, a format mix for the badges.
        private static func song(_ id: Int64, _ title: String, artist: String, album: String?,
                                 seconds: Int64) -> LibraryTrackDisplay {
            let format = ["MP3", "FLAC", "M4A", "FLAC", "FLAC"][Int(id) % 5]
            let lossy = format != "FLAC"
            return LibraryTrackDisplay(
                id: id, url: URL(filePath: "/fixture/\(id).\(format.lowercased())"), title: title,
                artistID: artist.isEmpty ? nil : 100 + id, artistName: artist,
                albumID: album == nil ? nil : 200 + id, albumName: album, format: format,
                trackNo: Int(id % 9) + 1, durationMs: seconds * 1000, year: 1990 + Int(id), artworkKey: nil,
                dateAdded: 0, sampleRate: lossy ? 44100 : 48000, bitDepth: lossy ? nil : 24, discNo: 1,
                fileSize: seconds * 600_000, playCount: id, lastPlayed: nil, albumArtistName: artist,
                genreName: "Soundtrack"
            )
        }
    }
#endif
