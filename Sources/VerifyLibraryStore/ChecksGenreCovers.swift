// ChecksGenreCovers — the S10.8 D5 genre-cover read, `genreCoverArtworkKeys(perGenre:)` (browse-grid
// decision 19: a genre tile's art is a 2×2 mosaic of the covers of its albums with the most songs):
//   GC-01 ranking — most songs first, a tie → the lower album id, cut at `perGenre` (4 by default; 1, 2
//         and a cap past the end too); a cap below 1 → an empty map. The Swift reference rule GC-05 and
//         GC-06 rely on gives the same hand-worked answer;
//   GC-02 membership — an album lists once however many of its songs are in the genre; two albums
//         wearing one cover show it once, at the better album's place; an album without art is skipped
//         (the next fills in) and a song with no album is ignored; a genre whose albums have no art, or
//         with no songs, is ABSENT; a song in two genres counts in both;
//   GC-03 empty — an empty library, and one whose albums have no art, return an empty map;
//   GC-04 plan — EXPLAIN QUERY PLAN reaches `tracks` by a SEARCH, never a full SCAN (the BR5 helpers);
//   GC-05 300 genres — a generated library (300 genres, 1,500 albums, 10,000 songs, covers missing and
//         shared) equals the reference rule for every genre, at the default cap and uncapped, and the
//         read stays under 100 ms (the slowest of five runs, the first included);
//   GC-06 write path — songs tagged and given art through the metadata write path and the end-of-pass
//         regroup: the read equals the reference rule over the public browse reads.
// GC-01/02/04/05 write their library straight into a production-migrated database (exact album ids
// and covers — what the ranking turns on); GC-03/06 go through the store's own write path.

import Foundation
import GRDB
import LibraryStore

// MARK: - Registration

func genreCoverCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "gc01-genre-cover-ranking", run: checkGenreCoverRanking),
        CheckCase(label: "gc02-genre-cover-membership", run: checkGenreCoverMembership),
        CheckCase(label: "gc03-genre-cover-empty", run: checkGenreCoverEmpty),
        CheckCase(label: "gc04-genre-cover-plan", run: checkGenreCoverQueryPlan),
        CheckCase(label: "gc05-genre-cover-300-genres", run: checkGenreCoverAtScale),
        CheckCase(label: "gc06-genre-cover-write-path", run: checkGenreCoverWritePath),
    ]
}

// MARK: - A library written straight into the tables

/// `count` songs on `album` (nil = no album), each in every one of `genres`.
private struct CoverSongs {
    let album: Int64?
    let count: Int
    let genres: [Int64]
}

/// Albums with their cover (nil = none), genre ids, and songs — numbered from 1 in order.
private struct CoverLibrary {
    let albums: [(id: Int64, cover: String?)]
    let genres: [Int64]
    let songs: [CoverSongs]

    /// Album id → cover, for the albums that have one.
    var covers: [Int64: String] {
        albums.reduce(into: [:]) { map, album in map[album.id] = album.cover }
    }

    /// One (genre, album) pair per song in a genre — what the reference rule counts.
    var memberships: [(genre: Int64, album: Int64?)] {
        songs.flatMap { run in
            (0 ..< run.count).flatMap { _ in run.genres.map { (genre: $0, album: run.album) } }
        }
    }

    /// Write the library into `db`, a fresh production-migrated database.
    func write(_ db: Database) throws {
        for cover in Set(albums.compactMap(\.cover)).sorted() {
            try db.execute(sql: "INSERT INTO artwork(content_hash, cache_path) VALUES (?, ?);",
                           arguments: [cover, "/cache/\(cover).jpg"])
        }
        let album = try db.cachedStatement(sql: "INSERT INTO albums(id, title, artwork_key) VALUES (?, ?, ?);")
        for (id, cover) in albums {
            try album.execute(arguments: [id, "Album \(id)", cover])
        }
        for genre in genres {
            try db.execute(sql: "INSERT INTO genres(id, name) VALUES (?, ?);", arguments: [genre, "Genre \(genre)"])
        }
        let song = try db.cachedStatement(sql: "INSERT INTO tracks(id, url, name, format, file_size, mtime, "
            + "album_id, date_added) VALUES (?, ?, ?, 'FLAC', 1, 1, ?, 1);")
        let membership = try db.cachedStatement(sql: "INSERT INTO track_genres(track_id, genre_id) VALUES (?, ?);")
        var songID: Int64 = 0
        for run in songs {
            for _ in 0 ..< run.count {
                songID += 1
                try song.execute(arguments: [songID, "/GC/\(songID).flac", "s\(songID)", run.album])
                for genre in run.genres {
                    try membership.execute(arguments: [songID, genre])
                }
            }
        }
    }
}

/// Build the database at `url` holding exactly `library` (the production migrator, then the rows).
private func writeCoverDatabase(at url: URL, _ library: CoverLibrary) throws {
    let queue = try DatabaseQueue(path: url.path)
    try fullMigrator().migrate(queue)
    try queue.write { db in try library.write(db) }
    try queue.close()
}

/// Open a store at `url` holding exactly `library`, the way the app opens one.
private func openCoverStore(at url: URL, _ library: CoverLibrary) async throws -> LibraryStore {
    try writeCoverDatabase(at: url, library)
    return try await LibraryStore(url: url, appBuild: "verify")
}

/// The genre-cover rule computed in Swift — the reference GC-05/GC-06 hold the read to: songs per
/// (genre, album) over albums with a cover; most songs first, a tie → the lower album id; a cover
/// already taken is skipped; at most `perGenre` per genre; a genre left with none is absent.
private func referenceGenreCovers(
    memberships: [(genre: Int64, album: Int64?)], covers: [Int64: String], perGenre: Int
) -> [Int64: [String]] {
    var songs: [Int64: [Int64: Int]] = [:]
    for membership in memberships {
        guard let album = membership.album, covers[album] != nil else { continue }
        songs[membership.genre, default: [:]][album, default: 0] += 1
    }
    var result: [Int64: [String]] = [:]
    for (genre, counts) in songs {
        let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var keys: [String] = []
        for (album, _) in ranked where keys.count < perGenre {
            if let key = covers[album], !keys.contains(key) {
                keys.append(key)
            }
        }
        if !keys.isEmpty {
            result[genre] = keys
        }
    }
    return result
}

// MARK: - The rules library (GC-01, GC-02, GC-04)

private let rock: Int64 = 1
private let jazz: Int64 = 2
private let ambient: Int64 = 3
private let silent: Int64 = 4
private let pop: Int64 = 5

/// Rock: album 3 has the most songs (6) but no art; 2 has 5 → c2; 4 (2 + a song also in Jazz) and 5
/// tie at 3 → c4 then c5; 6 wears album 2's cover with 2 songs; 1 has 2 → c1; 7 has 1 → c7.
/// Jazz: album 8 has 2 → c8, then 4's shared song → c4. Ambient: an art-less album and a song with no
/// album only. Silent: no songs. Pop: albums 10–14 tie at 2 songs; 10 and 12 wear one cover.
private let rulesLibrary = CoverLibrary(
    albums: [(1, "c1"), (2, "c2"), (3, nil), (4, "c4"), (5, "c5"), (6, "c2"), (7, "c7"), (8, "c8"), (9, nil),
             (10, "shared"), (11, "p11"), (12, "shared"), (13, "p13"), (14, "p14")],
    genres: [rock, jazz, ambient, silent, pop],
    songs: [
        CoverSongs(album: 1, count: 2, genres: [rock]), CoverSongs(album: 2, count: 5, genres: [rock]),
        CoverSongs(album: 3, count: 6, genres: [rock]), CoverSongs(album: 4, count: 2, genres: [rock]),
        CoverSongs(album: 4, count: 1, genres: [rock, jazz]), CoverSongs(album: 5, count: 3, genres: [rock]),
        CoverSongs(album: 6, count: 2, genres: [rock]), CoverSongs(album: 7, count: 1, genres: [rock]),
        CoverSongs(album: 8, count: 2, genres: [jazz]),
        CoverSongs(album: 9, count: 2, genres: [ambient]), CoverSongs(album: nil, count: 1, genres: [ambient]),
    ] + (10 ... 14).map { CoverSongs(album: $0, count: 2, genres: [pop]) }
)

/// The hand-worked uncapped answer for `rulesLibrary`.
private let rulesRanking: [Int64: [String]] = [
    rock: ["c2", "c4", "c5", "c1", "c7"], jazz: ["c8", "c4"], pop: ["shared", "p11", "p13", "p14"],
]

/// `rulesRanking` cut at `cap` (a genre cut to nothing is absent).
private func cappedRanking(_ cap: Int) -> [Int64: [String]] {
    rulesRanking.compactMapValues { keys in cap < 1 ? nil : Array(keys.prefix(cap)) }
}

// MARK: - GC-01 — ranking, ties and the cap

func checkGenreCoverRanking(number: Int, url: URL) async -> Bool {
    do {
        let store = try await openCoverStore(at: url, rulesLibrary)
        let defaulted = try await store.genreCoverArtworkKeys()
        guard defaulted == cappedRanking(4) else {
            printFail(number, "GC-01: the default cap gave \(defaulted), expected \(cappedRanking(4))"); return false
        }
        for cap in [1, 2, 3, 5, 10, Int.max, 0, -1] {
            let got = try await store.genreCoverArtworkKeys(perGenre: cap)
            guard got == cappedRanking(cap) else {
                printFail(number, "GC-01: perGenre \(cap) gave \(got), expected \(cappedRanking(cap))")
                return false
            }
        }
        let reference = referenceGenreCovers(
            memberships: rulesLibrary.memberships, covers: rulesLibrary.covers, perGenre: .max
        )
        guard reference == rulesRanking else {
            printFail(number, "GC-01: the Swift reference rule gave \(reference), not the hand-worked answer")
            return false
        }
        printPass(number, "GC-01 genre covers rank by songs in the genre, a tie → the lower album id (4 and 5 at "
            + "3 songs; Pop's five albums at 2), cut at perGenre (default 4; 1, 2, 3, 5, 10, Int.max exact; 0 and "
            + "-1 → empty); the Swift reference rule agrees with the hand-worked answer")
        return true
    } catch {
        printFail(number, "GC-01 threw: \(error)"); return false
    }
}

// MARK: - GC-02 — which albums and genres count

func checkGenreCoverMembership(number: Int, url: URL) async -> Bool {
    do {
        let store = try await openCoverStore(at: url, rulesLibrary)
        let all = try await store.genreCoverArtworkKeys(perGenre: .max)
        let rockKeys = all[rock] ?? []
        let popKeys = all[pop] ?? []
        // The default cap: an art-less album taking a slot would leave Rock fewer than four covers.
        let rockTopFour = try await store.genreCoverArtworkKeys()[rock] ?? []
        let rules: [(rule: String, holds: Bool)] = [
            ("an album lists once (album 2's five Rock songs → one c2)", rockKeys.count(where: { $0 == "c2" }) == 1),
            ("a cover on two albums shows once, at the better album's place (Rock's c2, Pop's shared)",
             rockKeys.first == "c2" && popKeys.first == "shared" && popKeys.count(where: { $0 == "shared" }) == 1),
            ("an album without art takes no slot (album 3 has the most Rock songs)", rockTopFour.count == 4),
            ("a genre whose albums have no art, or whose songs have no album, is absent", all[ambient] == nil),
            ("a genre with no songs is absent", all[silent] == nil),
            ("a song in two genres counts in both (album 4: second in Rock, second in Jazz)",
             rockKeys.firstIndex(of: "c4") == 1 && all[jazz] == ["c8", "c4"]),
        ]
        if let broken = rules.first(where: { !$0.holds }) {
            printFail(number, "GC-02: \(broken.rule) — the read gave \(all)"); return false
        }
        guard all == rulesRanking else {
            printFail(number, "GC-02: uncapped read gave \(all), expected \(rulesRanking)"); return false
        }
        printPass(number, "GC-02 genre-cover membership: an album lists once; a cover two albums wear shows "
            + "once at the better album's place; art-less albums and album-less songs are skipped; a genre with "
            + "no covered album or no songs is absent; a song in two genres counts in both")
        return true
    } catch {
        printFail(number, "GC-02 threw: \(error)"); return false
    }
}

// MARK: - GC-03 — nothing to show

func checkGenreCoverEmpty(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let empty = try await store.genreCoverArtworkKeys()
        guard empty.isEmpty else {
            printFail(number, "GC-03: an empty library gave \(empty)"); return false
        }
        // Two tagged songs on one album, in two genres, with no art — through the real write path.
        let root = try await store.addRoot(URL(fileURLWithPath: "/GC03"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            [makeScanned(path: "/GC03/a.flac", name: "a", inode: 301),
             makeScanned(path: "/GC03/b.flac", name: "b", inode: 302)],
            folderID: root, generation: gen
        )
        for (index, id) in ids.enumerated() {
            try await store.applyMetadata(
                TrackMetadata(title: "Bare \(index)", artistName: "Ann", albumTitle: "Bare",
                              albumArtistName: "Ann", trackNo: index + 1, genres: ["Rock", "Jazz"]),
                forTrack: id
            )
        }
        guard try await store.genres().count == 2, try await store.albums().count == 1 else {
            printFail(number, "GC-03: the art-less seed did not make 2 genres on 1 album"); return false
        }
        let bare = try await store.genreCoverArtworkKeys()
        guard bare.isEmpty else {
            printFail(number, "GC-03: a library whose albums have no art gave \(bare)"); return false
        }
        printPass(number, "GC-03 nothing to show: an empty library and a library whose albums have no art "
            + "(2 genres, 1 album) both return an empty map")
        return true
    } catch {
        printFail(number, "GC-03 threw: \(error)"); return false
    }
}

// MARK: - GC-04 — the query plan

func checkGenreCoverQueryPlan(number: Int, url: URL) async -> Bool {
    do {
        let store = try await openCoverStore(at: url, rulesLibrary)
        let details = try await store.explainGenreCoverArtworkKeysPlan()
        // The positive SEARCH also pins the alias (`t`) the BR5 scan tripwire watches, so a renamed
        // alias can't slip a full scan past it.
        guard details.contains(where: { $0.uppercased().hasPrefix("SEARCH T ") }) else {
            printFail(number, "GC-04: tracks (alias t) is not reached by a SEARCH: \(details)"); return false
        }
        guard !details.contains(where: detailIsTracksTableScan) else {
            printFail(number, "GC-04: the read SCANs the tracks table: \(details)"); return false
        }
        printPass(number, "GC-04 genre-cover EXPLAIN QUERY PLAN: tracks is reached by a SEARCH (by rowid from "
            + "track_genres), never a full SCAN — one walk of the memberships, no new index")
        return true
    } catch {
        printFail(number, "GC-04 threw: \(error)"); return false
    }
}

// MARK: - GC-05 — 300 genres

/// A deterministic scramble of `value` (Fibonacci hashing, high bits) — GC-05's seeded randomness.
private func scramble(_ value: Int) -> Int {
    Int((UInt64(value) &* 0x9E37_79B9_7F4A_7C15) >> 33)
}

/// 300 genres, 1,500 albums, 10,000 songs. Every 7th album has no art and every 50th wears its
/// neighbour's cover. A song (every 40th has no album) sits in its album's home genre (1–295) plus up
/// to two scrambled ones; a song with no cover also sits in one of genres 296–300, which therefore hold
/// no covered album and must be absent. Home albums give the top of each genre; the scattered single
/// songs give long runs of ties below them.
private func stressLibrary() -> CoverLibrary {
    let albums: [(id: Int64, cover: String?)] = (1 ... 1500).map { id in
        (Int64(id), id % 7 == 0 ? nil : "cover-\(id % 50 == 0 ? id - 1 : id)")
    }
    let covers = Set(albums.compactMap { $0.cover == nil ? nil : $0.id })
    let songs = (1 ... 10000).map { song -> CoverSongs in
        let album = song % 40 == 0 ? nil : Int64(scramble(song) % 1500 + 1)
        var genres: Set<Int64> = [album.map { $0 % 295 + 1 } ?? 296]
        for extra in 0 ..< scramble(song + 1_000_000) % 3 {
            genres.insert(Int64(scramble(song * 3 + extra + 2_000_000) % 295 + 1))
        }
        if album.map({ !covers.contains($0) }) ?? true {
            genres.insert(Int64(296 + scramble(song + 3_000_000) % 5))
        }
        return CoverSongs(album: album, count: 1, genres: genres.sorted())
    }
    return CoverLibrary(albums: albums, genres: (1 ... 300).map { Int64($0) }, songs: songs)
}

func checkGenreCoverAtScale(number: Int, url: URL) async -> Bool {
    do {
        let library = stressLibrary()
        let store = try await openCoverStore(at: url, library)
        let clock = ContinuousClock()
        var slowest = Duration.zero
        var keys: [Int64: [String]] = [:]
        for _ in 0 ..< 5 {
            let start = clock.now
            keys = try await store.genreCoverArtworkKeys()
            slowest = max(slowest, clock.now - start)
        }
        let memberships = library.memberships
        let expected = referenceGenreCovers(memberships: memberships, covers: library.covers, perGenre: 4)
        let absent = (296 ... 300).allSatisfy { expected[$0] == nil }
        guard keys == expected, absent, expected.count == 295 else {
            let wrong = expected.keys.sorted().first { keys[$0] != expected[$0] }.map { "genre \($0)" } ?? "none"
            printFail(number, "GC-05: \(keys.count) genres read vs \(expected.count) expected (296–300 absent: "
                + "\(absent)); first wrong: \(wrong)"); return false
        }
        let uncapped = try await store.genreCoverArtworkKeys(perGenre: .max)
        guard uncapped == referenceGenreCovers(memberships: memberships, covers: library.covers, perGenre: .max)
        else { printFail(number, "GC-05: the uncapped ranking differs from the reference rule"); return false }
        let milliseconds = slowest / .milliseconds(1)
        guard milliseconds < 100 else {
            printFail(number, "GC-05: the read took \(milliseconds) ms (bound 100 ms)"); return false
        }
        printPass(number, "GC-05 300 genres / 1,500 albums / 10,000 songs (\(memberships.count) memberships): "
            + "the read equals the reference rule for all 295 covered genres (296–300 absent), capped and "
            + "uncapped; slowest of 5 reads \(String(format: "%.1f", milliseconds)) ms (bound 100 ms)")
        return true
    } catch {
        printFail(number, "GC-05 threw: \(error)"); return false
    }
}

// MARK: - GC-06 — through the write path

/// One song for GC-06: its file, album, genres and embedded cover (nil = none).
private struct WrittenSong {
    let file: String
    let album: String
    let genres: [String]
    let cover: String?
}

/// Alpha (2 Rock songs, art), Beta (1 song in Rock AND Jazz, art), Gamma (3 Jazz songs, no art),
/// Delta (1 Jazz song, art).
private let writtenSongs = [
    WrittenSong(file: "a1.flac", album: "Alpha", genres: ["Rock"], cover: "art-alpha"),
    WrittenSong(file: "a2.flac", album: "Alpha", genres: ["Rock"], cover: "art-alpha"),
    WrittenSong(file: "b1.flac", album: "Beta", genres: ["Rock", "Jazz"], cover: "art-beta"),
    WrittenSong(file: "g1.flac", album: "Gamma", genres: ["Jazz"], cover: nil),
    WrittenSong(file: "g2.flac", album: "Gamma", genres: ["Jazz"], cover: nil),
    WrittenSong(file: "g3.flac", album: "Gamma", genres: ["Jazz"], cover: nil),
    WrittenSong(file: "d1.flac", album: "Delta", genres: ["Jazz"], cover: "art-delta"),
]

/// The reference rule over the public browse reads: each genre's songs (`tracksDisplay(inGenre:)`)
/// and each album's cover (`albums()`).
private func referenceFromBrowseReads(_ store: LibraryStore) async throws -> [Int64: [String]] {
    var memberships: [(genre: Int64, album: Int64?)] = []
    for genre in try await store.genres() {
        memberships += try await store.tracksDisplay(inGenre: genre.id).map { (genre: genre.id, album: $0.albumID) }
    }
    let covers = try await store.albums().reduce(into: [Int64: String]()) { $0[$1.id] = $1.artworkKey }
    return referenceGenreCovers(memberships: memberships, covers: covers, perGenre: 4)
}

func checkGenreCoverWritePath(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/GC06"))
        let gen = try await store.beginScanGeneration()
        for (index, song) in writtenSongs.enumerated() {
            let scanned = makeScanned(path: "/GC06/\(song.file)", name: song.file, inode: Int64(600 + index))
            guard let id = try await store.upsert([scanned], folderID: root, generation: gen).first else {
                printFail(number, "GC-06: seed upsert failed"); return false
            }
            let art = song.cover.map {
                ArtworkLink(contentHash: $0, cachePath: "/cache/\($0).jpg",
                            pixelSize: CGSize(width: 600, height: 600), byteSize: 1024)
            }
            let meta = TrackMetadata(title: song.file, artistName: "Ann", albumTitle: song.album,
                                     albumArtistName: "Ann", genres: song.genres)
            try await store.applyExtractedResult(trackID: id, meta: meta, artwork: art, generation: gen)
        }
        _ = try await store.refreshDerivedFacets()
        let keys = try await store.genreCoverArtworkKeys()
        let expected = try await referenceFromBrowseReads(store)
        let byName = try await store.genres().reduce(into: [String: [String]]()) { $0[$1.name] = keys[$1.id] }
        // Beta and Delta tie at one Jazz song: their order is the album ids the regroup gave them.
        guard keys == expected, byName["Rock"] == ["art-alpha", "art-beta"],
              Set(byName["Jazz"] ?? []) == ["art-beta", "art-delta"], byName["Jazz"]?.count == 2 else {
            printFail(number, "GC-06: through the write path the read gave \(byName)"); return false
        }
        printPass(number, "GC-06 genre covers through the write path (tags + art → end-of-pass regroup): the read "
            + "equals the reference rule over the public browse reads — Rock [Alpha, Beta], Jazz {Beta, Delta}, "
            + "the art-less Gamma skipped though it has the most Jazz songs")
        return true
    } catch {
        printFail(number, "GC-06 threw: \(error)"); return false
    }
}
