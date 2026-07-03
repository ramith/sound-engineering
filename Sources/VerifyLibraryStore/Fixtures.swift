// Fixtures — the synthetic library the B–F cases assert against (design §6).
//
// `seedFixtureLibrary` builds a deterministic library THROUGH the real DAO (addRoot
// + upsert + applyMetadata), so it exercises the actual write path — including the
// M1 total-album-key resolution — rather than hand-inserting rows. It returns a
// computed `FixtureExpectations` so the facet checks (C) assert counts against a
// value derived from the fixture definition, catching JOIN fan-out.
//
// Composition (per §6): 3 named artists × 2 albums each, a "Various Artists"
// compilation, an all-default-facet UNTAGGED album (two 'Greatest Hits' tracks with
// no album-artist / no year — must collapse to ONE album, M1), across 2 years and 3
// OVERLAPPING genres, the CONFUSABLE `/Music/Rock` vs `/Music/RockAndRoll` folders,
// and at least one LOOSE file (folder NULL, outside every root).

import Foundation
import LibraryStore

// MARK: - Expectations (computed from the fixture definition)

/// The counts/identities the fixture guarantees. Facet checks assert against THIS
/// (not magic numbers) so a JOIN fan-out or a resolution bug is caught structurally.
struct FixtureExpectations {
    let totalTracks: Int
    /// Distinct albums AFTER M1 resolution (the two untagged 'Greatest Hits' = ONE).
    let albumCount: Int
    /// Distinct named artists (EXCLUDING the id-0 sentinel).
    let artistCount: Int
    let genreCount: Int
    /// Track count of the collapsed untagged 'Greatest Hits' album (must be 2).
    let untaggedAlbumTrackCount: Int
    /// rootID → number of tracks directly under that root.
    let tracksPerRoot: [Int64: Int]
    /// The `/Music/Rock` root id and its EXACT track count (path-boundary check).
    let rockRootID: Int64
    let rockRootTrackCount: Int
    /// The `/Music/RockAndRoll` root id and its EXACT track count.
    let rockAndRollRootID: Int64
    let rockAndRollRootTrackCount: Int
    /// The loose track's id (folder NULL) — used by the FS-4 survival check.
    let looseTrackID: Int64
    /// genre name → distinct track count (for the DISTINCT-count assertion).
    let genreTrackCounts: [String: Int]
}

// MARK: - Seed

/// A single fixture track definition (before it becomes a ScannedFile + metadata).
private struct FixtureTrack {
    let fileName: String
    let title: String
    let artist: String?
    let album: String?
    let albumArtist: String?
    let year: Int?
    let trackNo: Int?
    let genres: [String]
}

/// Seed the synthetic library through the DAO and return its expectations.
/// `rootPath` folders are created via `addRoot`; tracks are `upsert`ed under them
/// (or loose) then decorated via `applyMetadata`.
func seedFixtureLibrary(_ store: LibraryStore) async throws -> FixtureExpectations {
    // Two named-artist folders + the two confusable Rock folders.
    let popRootID = try await store.addRoot(URL(fileURLWithPath: "/Music/Pop"))
    let jazzRootID = try await store.addRoot(URL(fileURLWithPath: "/Music/Jazz"))
    let rockRootID = try await store.addRoot(URL(fileURLWithPath: "/Music/Rock"))
    let rockAndRollRootID = try await store.addRoot(URL(fileURLWithPath: "/Music/RockAndRoll"))

    let generation = try await store.beginScanGeneration()

    // Root → its tracks (named artists × 2 albums + a compilation + the untagged album).
    let popTracks = popFixtureTracks()
    let jazzTracks = jazzFixtureTracks()
    let rockTracks = rockFixtureTracks()
    let rockAndRollTracks = rockAndRollFixtureTracks()

    try await seed(store, tracks: popTracks, root: "/Music/Pop", folderID: popRootID, gen: generation)
    try await seed(store, tracks: jazzTracks, root: "/Music/Jazz", folderID: jazzRootID, gen: generation)
    try await seed(store, tracks: rockTracks, root: "/Music/Rock", folderID: rockRootID, gen: generation)
    try await seed(
        store, tracks: rockAndRollTracks, root: "/Music/RockAndRoll",
        folderID: rockAndRollRootID, gen: generation
    )

    // One LOOSE file (folder NULL, outside every root) — Req 2.
    let looseFile = ScannedFile(
        url: URL(fileURLWithPath: "/Downloads/loose-single.flac"),
        name: "loose-single", format: "FLAC", fileSize: 5000, mtime: 1000
    )
    let looseTrackID = try await store.addLooseFile(looseFile)
    try await store.applyMetadata(
        TrackMetadata(title: "Loose Single", artistName: "Loose Artist",
                      albumTitle: "Loose Album", albumArtistName: "Loose Artist",
                      year: 2020, trackNo: 1, genres: ["Electronic"]),
        forTrack: looseTrackID
    )

    return computeExpectations(
        allDefs: popTracks + jazzTracks + rockTracks + rockAndRollTracks,
        looseGenres: ["Electronic"], looseArtist: "Loose Artist", looseAlbum: "Loose Album",
        rootCounts: [
            popRootID: popTracks.count, jazzRootID: jazzTracks.count,
            rockRootID: rockTracks.count, rockAndRollRootID: rockAndRollTracks.count,
        ],
        rockRootID: rockRootID, rockCount: rockTracks.count,
        rockAndRollRootID: rockAndRollRootID, rockAndRollCount: rockAndRollTracks.count,
        looseTrackID: looseTrackID
    )
}

/// Upsert + decorate one folder's fixture tracks.
private func seed(
    _ store: LibraryStore, tracks: [FixtureTrack], root: String, folderID: Int64, gen: Int64
) async throws {
    var mtime: Int64 = 2000
    for track in tracks {
        let url = URL(fileURLWithPath: "\(root)/\(track.fileName)")
        let scanned = ScannedFile(
            url: url, relativePath: "", name: track.fileName, format: "FLAC",
            fileSize: 4096, mtime: mtime
        )
        let ids = try await store.upsert([scanned], folderID: folderID, generation: gen)
        guard let id = ids.first else { continue }
        try await store.applyMetadata(
            TrackMetadata(
                title: track.title, artistName: track.artist, albumTitle: track.album,
                albumArtistName: track.albumArtist, year: track.year, trackNo: track.trackNo,
                genres: track.genres, durationMs: 180_000
            ),
            forTrack: id
        )
        mtime += 1
    }
}

// MARK: - Fixture definitions (deterministic)

private func popFixtureTracks() -> [FixtureTrack] {
    // Artist A: 2 albums (2021, 2022); genres Pop + overlapping Electronic.
    [
        FixtureTrack(fileName: "a1.flac", title: "A One", artist: "Artist A", album: "Alpha",
                     albumArtist: "Artist A", year: 2021, trackNo: 1, genres: ["Pop"]),
        FixtureTrack(fileName: "a2.flac", title: "A Two", artist: "Artist A", album: "Alpha",
                     albumArtist: "Artist A", year: 2021, trackNo: 2, genres: ["Pop", "Electronic"]),
        FixtureTrack(fileName: "a3.flac", title: "A Three", artist: "Artist A", album: "Beta",
                     albumArtist: "Artist A", year: 2022, trackNo: 1, genres: ["Pop"]),
        FixtureTrack(fileName: "a4.flac", title: "A Four", artist: "Artist A", album: "Beta",
                     albumArtist: "Artist A", year: 2022, trackNo: 2, genres: ["Electronic"]),
    ]
}

private func jazzFixtureTracks() -> [FixtureTrack] {
    // Artist B: 2 albums (2021, 2022); genre Jazz + overlapping Electronic.
    [
        FixtureTrack(fileName: "b1.flac", title: "B One", artist: "Artist B", album: "Gamma",
                     albumArtist: "Artist B", year: 2021, trackNo: 1, genres: ["Jazz"]),
        FixtureTrack(fileName: "b2.flac", title: "B Two", artist: "Artist B", album: "Gamma",
                     albumArtist: "Artist B", year: 2021, trackNo: 2, genres: ["Jazz"]),
        FixtureTrack(fileName: "b3.flac", title: "B Three", artist: "Artist B", album: "Delta",
                     albumArtist: "Artist B", year: 2022, trackNo: 1, genres: ["Jazz", "Electronic"]),
        FixtureTrack(fileName: "b4.flac", title: "B Four", artist: "Artist B", album: "Delta",
                     albumArtist: "Artist B", year: 2022, trackNo: 2, genres: ["Jazz"]),
    ]
}

private func rockFixtureTracks() -> [FixtureTrack] {
    // Artist C: 2 albums + a Various-Artists compilation. Distinct folder from R&R.
    [
        FixtureTrack(fileName: "c1.flac", title: "C One", artist: "Artist C", album: "Epsilon",
                     albumArtist: "Artist C", year: 2021, trackNo: 1, genres: ["Rock"]),
        FixtureTrack(fileName: "c2.flac", title: "C Two", artist: "Artist C", album: "Epsilon",
                     albumArtist: "Artist C", year: 2021, trackNo: 2, genres: ["Rock"]),
        FixtureTrack(fileName: "c3.flac", title: "C Three", artist: "Artist C", album: "Zeta",
                     albumArtist: "Artist C", year: 2022, trackNo: 1, genres: ["Rock", "Electronic"]),
        // Compilation: same album, DIFFERENT track artists, one album-artist.
        FixtureTrack(fileName: "comp1.flac", title: "Comp One", artist: "Artist A", album: "Various Hits",
                     albumArtist: "Various Artists", year: 2023, trackNo: 1, genres: ["Pop"]),
        FixtureTrack(fileName: "comp2.flac", title: "Comp Two", artist: "Artist B", album: "Various Hits",
                     albumArtist: "Various Artists", year: 2023, trackNo: 2, genres: ["Jazz"]),
    ]
}

private func rockAndRollFixtureTracks() -> [FixtureTrack] {
    // The CONFUSABLE sibling of /Music/Rock — a path-prefix bug would fold these
    // into the Rock folder facet. PLUS the two all-default-facet untagged tracks
    // (no artist / no album-artist / no year) that M1 must collapse to ONE album.
    [
        FixtureTrack(fileName: "rr1.flac", title: "RR One", artist: "Artist C", album: "Eta",
                     albumArtist: "Artist C", year: 2022, trackNo: 1, genres: ["Rock"]),
        FixtureTrack(fileName: "rr2.flac", title: "RR Two", artist: "Artist C", album: "Eta",
                     albumArtist: "Artist C", year: 2022, trackNo: 2, genres: ["Rock"]),
        // Two UNTAGGED tracks: album 'Greatest Hits', NO album-artist, NO year → the
        // M1 total key collapses them to ONE ('Greatest Hits', 0, 0) album.
        FixtureTrack(fileName: "untagged1.flac", title: "Untitled 1", artist: nil,
                     album: "Greatest Hits", albumArtist: nil, year: nil, trackNo: nil, genres: []),
        FixtureTrack(fileName: "untagged2.flac", title: "Untitled 2", artist: nil,
                     album: "Greatest Hits", albumArtist: nil, year: nil, trackNo: nil, genres: []),
    ]
}

// MARK: - Expectation computation

// PERMANENT reason="test fixture expectation builder (Verify tool)"
// swiftlint:disable:next function_parameter_count
private func computeExpectations(
    allDefs: [FixtureTrack], looseGenres: [String], looseArtist: String, looseAlbum: String,
    rootCounts: [Int64: Int], rockRootID: Int64, rockCount: Int,
    rockAndRollRootID: Int64, rockAndRollCount: Int, looseTrackID: Int64
) -> FixtureExpectations {
    let totalTracks = allDefs.count + 1 // + the loose track

    // Album count via the M1 total key: (title, albumArtist ?? sentinel, year ?? 0).
    var albumKeys = Set<String>()
    for def in allDefs where def.album != nil {
        albumKeys.insert(albumKey(title: def.album, albumArtist: def.albumArtist, year: def.year))
    }
    albumKeys.insert(albumKey(title: looseAlbum, albumArtist: looseArtist, year: 2020))
    let albumCount = albumKeys.count

    // Named artists (track-artist ∪ album-artist ∪ loose), EXCLUDING the sentinel.
    var artists = Set<String>()
    for def in allDefs {
        if let artist = def.artist { artists.insert(artist) }
        if let albumArtist = def.albumArtist { artists.insert(albumArtist) }
    }
    artists.insert(looseArtist)
    let artistCount = artists.count

    // Genre DISTINCT-track counts.
    var genreTrackCounts: [String: Int] = [:]
    for def in allDefs {
        for genre in Set(def.genres) {
            genreTrackCounts[genre, default: 0] += 1
        }
    }
    for genre in Set(looseGenres) {
        genreTrackCounts[genre, default: 0] += 1
    }
    let genreCount = genreTrackCounts.count

    let untaggedCount = allDefs.filter {
        $0.album == "Greatest Hits" && $0.albumArtist == nil && $0.year == nil
    }.count

    return FixtureExpectations(
        totalTracks: totalTracks, albumCount: albumCount, artistCount: artistCount,
        genreCount: genreCount, untaggedAlbumTrackCount: untaggedCount, tracksPerRoot: rootCounts,
        rockRootID: rockRootID, rockRootTrackCount: rockCount,
        rockAndRollRootID: rockAndRollRootID, rockAndRollRootTrackCount: rockAndRollCount,
        looseTrackID: looseTrackID, genreTrackCounts: genreTrackCounts
    )
}

/// The M1 total-album-key string used to compute the expected album count — mirrors
/// the store's resolution (album-artist defaults to the sentinel, year to 0).
private func albumKey(title: String?, albumArtist: String?, year: Int?) -> String {
    "\(title ?? "")|\(albumArtist ?? "<sentinel>")|\(year ?? 0)"
}
