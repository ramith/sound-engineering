// ChecksCRUD — case B (CRUD / integrity) + case C (facets). Companion to
// Checks.swift / main.swift; same VerifyAUGraph idiom (Bool return, numbered
// PASS/FAIL, temp DBs under test-data/). Drives the S8.1b DAO through the actor.

import Foundation
import LibraryStore

// MARK: - Small DAO fixture helpers

/// A minimal single-track scanned file for CRUD round-trips.
func makeScanned(
    path: String, name: String, size: Int64 = 4096, mtime: Int64 = 1000, inode: Int64? = 42
) -> ScannedFile {
    ScannedFile(
        url: URL(fileURLWithPath: path), relativePath: "", name: name, format: "FLAC",
        fileSize: size, mtime: mtime, inode: inode
    )
}

// MARK: - B — CRUD / integrity

/// B: insert/read/update/delete round-trip; UNIQUE(url) → typed URLConflict on a
/// move collision; FK integrity (foreign_keys ON) — folder ON DELETE SET NULL
/// detaches tracks to loose; and M1 (two untagged 'Greatest Hits' collapse to ONE).
func checkCRUDIntegrity(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let rootID = try await store.addRoot(URL(fileURLWithPath: "/Music/B"))

        // Insert → read.
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/B/one.flac", name: "one")],
            folderID: rootID, generation: generation
        )
        guard let trackID = ids.first, let inserted = try await store.track(id: trackID) else {
            printFail(number, "CRUD: insert/read failed"); return false
        }
        guard inserted.name == "one", inserted.folderID == rootID, inserted.inode == 42 else {
            printFail(number, "CRUD: round-trip mismatch (\(inserted))"); return false
        }

        // Update via applyMetadata → read back.
        try await store.applyMetadata(TrackMetadata(title: "One!", artistName: "B Artist"), forTrack: trackID)
        guard let updated = try await store.track(id: trackID), updated.title == "One!" else {
            printFail(number, "CRUD: update-in-place not reflected"); return false
        }

        // Delete → gone.
        try await store.delete(id: trackID)
        guard try await store.track(id: trackID) == nil else {
            printFail(number, "CRUD: delete did not remove the row"); return false
        }

        guard try await checkUniqueConflict(store, number: number, rootID: rootID) else { return false }
        guard try await checkFolderDetach(store, number: number) else { return false }
        guard try await checkUntaggedAlbumCollapse(store, number: number) else { return false }

        printPass(number, "CRUD/integrity: insert/read/update/delete round-trips; UNIQUE(url) → typed "
            + "URLConflict; folder ON DELETE SET NULL detaches to loose; M1 two untagged albums collapse to 1")
        return true
    } catch {
        printFail(number, "CRUD/integrity threw: \(error)"); return false
    }
}

/// UNIQUE(url): moving track X onto Y's url must throw a typed `URLConflict`.
private func checkUniqueConflict(_ store: LibraryStore, number: Int, rootID: Int64) async throws -> Bool {
    let generation = try await store.beginScanGeneration()
    let ids = try await store.upsert(
        [makeScanned(path: "/Music/B/x.flac", name: "x"),
         makeScanned(path: "/Music/B/y.flac", name: "y")],
        folderID: rootID, generation: generation
    )
    guard ids.count == 2 else { printFail(number, "CRUD: two-row seed failed"); return false }
    let (xID, yID) = (ids[0], ids[1])
    do {
        try await store.moveTrack(id: xID, newURL: URL(fileURLWithPath: "/Music/B/y.flac"), newFolderID: rootID)
        printFail(number, "CRUD: moveTrack onto an occupied url did NOT throw")
        return false
    } catch let conflict as URLConflict {
        guard conflict.existingID == yID else {
            printFail(number, "CRUD: URLConflict.existingID \(String(describing: conflict.existingID)) != \(yID)")
            return false
        }
    }
    return true
}

/// FK: deleting a folder detaches its tracks to loose (folder_id NULL), NOT cascade.
private func checkFolderDetach(_ store: LibraryStore, number: Int) async throws -> Bool {
    let folderID = try await store.addRoot(URL(fileURLWithPath: "/Music/Detach"))
    let generation = try await store.beginScanGeneration()
    let ids = try await store.upsert(
        [makeScanned(path: "/Music/Detach/d.flac", name: "d")],
        folderID: folderID, generation: generation
    )
    guard let detachID = ids.first else { printFail(number, "CRUD: detach seed failed"); return false }
    try await store.removeRoot(id: folderID)
    // With no playlist referencing it, removeRoot deletes the now-loose row entirely.
    guard try await store.track(id: detachID) == nil else {
        printFail(number, "CRUD: removeRoot did not delete the unreferenced (detached) track")
        return false
    }
    return true
}

/// M1: two untagged tracks with album 'Greatest Hits', no album-artist, no year must
/// resolve to ONE album (title, sentinel, 0), not two.
private func checkUntaggedAlbumCollapse(_ store: LibraryStore, number: Int) async throws -> Bool {
    let folderID = try await store.addRoot(URL(fileURLWithPath: "/Music/Untagged"))
    let generation = try await store.beginScanGeneration()
    let ids = try await store.upsert(
        [makeScanned(path: "/Music/Untagged/u1.flac", name: "u1"),
         makeScanned(path: "/Music/Untagged/u2.flac", name: "u2")],
        folderID: folderID, generation: generation
    )
    for id in ids {
        try await store.applyMetadata(TrackMetadata(albumTitle: "Greatest Hits"), forTrack: id)
    }
    let greatestHits = try await store.albums().filter { $0.title == "Greatest Hits" }
    guard greatestHits.count == 1 else {
        printFail(number, "M1: untagged 'Greatest Hits' produced \(greatestHits.count) albums, expected 1")
        return false
    }
    guard greatestHits[0].albumArtistID == 0, greatestHits[0].year == 0,
          greatestHits[0].trackCount == 2 else {
        printFail(number, "M1: collapsed album facet wrong (\(greatestHits[0]))")
        return false
    }
    return true
}

// MARK: - C — facets

/// C: album/artist/genre/year facets + a real path-BOUNDARY folder check
/// (/Music/Rock must NOT match /Music/RockAndRoll), empty-result cleanliness, and
/// every count asserted against the computed FixtureExpectations (catches fan-out).
func checkFacets(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let expected = try await seedFixtureLibrary(store)

        guard try await checkFacetCounts(store, number: number, expected: expected) else { return false }
        guard try await checkFolderBoundary(store, number: number, expected: expected) else { return false }
        guard try await checkGenreDistinctCounts(store, number: number, expected: expected) else { return false }

        printPass(number, "facets: albums=\(expected.albumCount), artists=\(expected.artistCount), "
            + "genres=\(expected.genreCount) all match computed expectations; /Music/Rock vs "
            + "/Music/RockAndRoll path boundary respected; genre counts use DISTINCT (no JOIN fan-out)")
        return true
    } catch {
        printFail(number, "facets threw: \(error)"); return false
    }
}

/// Album/artist/genre/track counts + a year-sorted spot check, all vs expectations.
private func checkFacetCounts(
    _ store: LibraryStore, number: Int, expected: FixtureExpectations
) async throws -> Bool {
    let albums = try await store.albums(sortedBy: .title)
    let artists = try await store.artists(sortedBy: .title)
    let genres = try await store.genres()
    let total = try await store.trackCount()

    guard albums.count == expected.albumCount else {
        printFail(number, "facets: album count \(albums.count) != \(expected.albumCount)"); return false
    }
    guard artists.count == expected.artistCount else {
        printFail(number, "facets: artist count \(artists.count) != \(expected.artistCount) "
            + "(sentinel leaked into the artist list?)"); return false
    }
    guard genres.count == expected.genreCount else {
        printFail(number, "facets: genre count \(genres.count) != \(expected.genreCount)"); return false
    }
    guard total == expected.totalTracks else {
        printFail(number, "facets: total tracks \(total) != \(expected.totalTracks)"); return false
    }
    // The collapsed untagged album carries exactly its 2 tracks (no over-count).
    let untagged = albums.filter { $0.title == "Greatest Hits" }
    guard untagged.count == 1, untagged[0].trackCount == expected.untaggedAlbumTrackCount else {
        printFail(number, "facets: untagged album track count wrong "
            + "(\(untagged.map(\.trackCount)) vs \(expected.untaggedAlbumTrackCount))"); return false
    }
    // Year-sorted albums are non-decreasing in year.
    let byYear = try await store.albums(sortedBy: .year)
    guard isNonDecreasing(byYear.map(\.year)) else {
        printFail(number, "facets: albums(sortedBy: .year) not year-ordered"); return false
    }
    return true
}

/// The path-boundary check: /Music/Rock and /Music/RockAndRoll are DISTINCT roots
/// with distinct track sets; querying one must not include the other's tracks.
private func checkFolderBoundary(
    _ store: LibraryStore, number: Int, expected: FixtureExpectations
) async throws -> Bool {
    let rockTracks = try await store.tracks(inFolder: expected.rockRootID)
    let rockAndRollTracks = try await store.tracks(inFolder: expected.rockAndRollRootID)
    guard rockTracks.count == expected.rockRootTrackCount else {
        printFail(number, "folder boundary: /Music/Rock has \(rockTracks.count) tracks, "
            + "expected \(expected.rockRootTrackCount) — did it absorb /Music/RockAndRoll?"); return false
    }
    guard rockAndRollTracks.count == expected.rockAndRollRootTrackCount else {
        printFail(number, "folder boundary: /Music/RockAndRoll has \(rockAndRollTracks.count) tracks, "
            + "expected \(expected.rockAndRollRootTrackCount)"); return false
    }
    // No url from one folder appears in the other (disjoint sets).
    let rockURLs = Set(rockTracks.map(\.url))
    let rockAndRollURLs = Set(rockAndRollTracks.map(\.url))
    guard rockURLs.isDisjoint(with: rockAndRollURLs) else {
        printFail(number, "folder boundary: /Music/Rock and /Music/RockAndRoll share tracks"); return false
    }
    // Empty-result cleanliness: a folder id with no tracks returns [].
    let empty = try await store.tracks(inFolder: 999_999)
    guard empty.isEmpty else {
        printFail(number, "folder boundary: unknown folder returned \(empty.count) tracks, expected 0")
        return false
    }
    return true
}

/// Genre counts must be DISTINCT-per-track (a track in two genres is not double
/// counted anywhere) and match the computed per-genre expectations.
private func checkGenreDistinctCounts(
    _ store: LibraryStore, number: Int, expected: FixtureExpectations
) async throws -> Bool {
    let genres = try await store.genres()
    for facet in genres {
        guard let want = expected.genreTrackCounts[facet.name] else {
            printFail(number, "genre counts: unexpected genre '\(facet.name)'"); return false
        }
        guard facet.trackCount == want else {
            printFail(number, "genre counts: '\(facet.name)' has \(facet.trackCount), expected \(want) "
                + "(JOIN fan-out?)"); return false
        }
    }
    return true
}

// MARK: - Local helpers

/// True if `values` is non-decreasing.
func isNonDecreasing(_ values: [Int]) -> Bool {
    zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
}
