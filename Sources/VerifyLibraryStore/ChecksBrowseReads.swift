// ChecksBrowseReads — the S9.1/S9.6 FACET browse-read DAO checks (design §3, test plan §10).
//
// Drives the REAL LibraryStore on a REAL temp store built from `seedFixtureLibrary`, asserting the
// facet drill-down / count reads against DERIVED `FixtureExpectations` sets (never magic numbers).
// Same VerifyAUGraph idiom (Bool return, one numbered PASS line each):
//   BR2  albums/tracksDisplay(byArtist:) sets + order + resolved artist/album names.
//   BR2b albums/tracksDisplay(inGenre:) sets via track_genres JOIN, no fan-out.
//   BR2c years()/yearFacets()/albums(inYear:)/tracksDisplay(inYear:) sets + counts (TRACK-year).
//   BR3  album(id:)/artist(id:)/genre(id:) equal the matching list entry; a nonexistent id → nil.
//   BR3b artist reads never surface the id-0 unknown-artist sentinel.
//   BR4  pagination window: adjacent pages no dup/gap; limit == nil == unbounded.
//   BR7  ArtistFacet.trackCount (track-artist lens) == detail == fixture; 0-song album-artist.
//   BR8  null-year omission + 0-song genre reachability (ad-hoc stores).
//
// Sibling concerns split into their own files: BR1 artwork-path map → ChecksArtworkMap; BR5 EXPLAIN
// query-plan tripwire + the shared `detailUsesIndex`/`detailIsTracksTableScan` helpers → ChecksQueryPlan.

import Foundation
import LibraryScan
import LibraryStore

// MARK: - BR2 — artist drill-down (albums + display tracks, names resolved)

func checkBrowseArtistDrilldown(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let expected = try await seedFixtureLibrary(store)
        // Artist B DISCRIMINATES .year from .title order: albums Gamma(2021)/Delta(2022)
        // sort [Gamma, Delta] by year but [Delta, Gamma] by title.
        guard let artistB = try await store.artists().first(where: { $0.name == "Artist B" }) else {
            printFail(number, "BR2: seed missing Artist B"); return false
        }
        guard try await checkArtistAlbums(store, artistID: artistB.id, number: number, expected: expected),
              try await checkArtistTracks(store, artistID: artistB.id, number: number, expected: expected),
              try await pinByArtistLensSplit(baseURL: url, number: number) else { return false }
        printPass(number, "BR2: albums(byArtist:) year-ordered (distinct from title order) + "
            + "tracksDisplay(byArtist:) = expected sets w/ resolved artist/album names (incl. the "
            + "compilation); the album-artist lens is pinned distinct from the track-artist lens")
        return true
    } catch {
        printFail(number, "BR2 threw: \(error)"); return false
    }
}

/// Assert `albums(byArtist:)` = the album-artist's albums, year-ordered AND that the
/// .year order is genuinely distinct from .title order (so a .year→.title bug is caught).
private func checkArtistAlbums(
    _ store: LibraryStore, artistID: Int64, number: Int, expected: FixtureExpectations
) async throws -> Bool {
    let byYear = try await store.albums(byArtist: artistID, sortedBy: .year)
    let byTitle = try await store.albums(byArtist: artistID, sortedBy: .title)
    guard Set(byYear.map(\.title)) == (expected.albumsByAlbumArtist["Artist B"] ?? []) else {
        printFail(number, "BR2: albums(byArtist:) set != expected"); return false
    }
    guard isNonDecreasing(byYear.map(\.year)), byYear.map(\.title) != byTitle.map(\.title) else {
        printFail(number, "BR2: .year order not distinct from .title order (a .year→.title bug hides here)")
        return false
    }
    return true
}

/// Assert `tracksDisplay(byArtist:)` = the track-artist's tracks in album/disc/track
/// order with resolved artist/album names, incl. the compilation row (a different
/// album-artist) resolving correctly across the LEFT JOIN.
private func checkArtistTracks(
    _ store: LibraryStore, artistID: Int64, number: Int, expected: FixtureExpectations
) async throws -> Bool {
    let tracks = try await store.tracksDisplay(byArtist: artistID)
    let albumIDs = tracks.compactMap { $0.albumID.map(Int.init) }
    guard Set(tracks.map(\.title)) == (expected.tracksByArtist["Artist B"] ?? []) else {
        printFail(number, "BR2: tracksDisplay(byArtist:) set != expected"); return false
    }
    guard albumIDs.count == tracks.count, isNonDecreasing(albumIDs) else {
        printFail(number, "BR2: tracksDisplay(byArtist:) not in album/disc/track order"); return false
    }
    guard tracks.allSatisfy({ $0.artistName == "Artist B" && ($0.albumName ?? "").isEmpty == false }) else {
        printFail(number, "BR2: Display rows missing resolved artistName/albumName"); return false
    }
    guard let comp = tracks.first(where: { $0.title == "Comp Two" }),
          comp.albumName == "Various Hits", comp.artistName == "Artist B" else {
        printFail(number, "BR2: compilation row name resolution wrong"); return false
    }
    return true
}

/// Pin the deliberate byArtist LENS SPLIT on a small AD-HOC store: a track whose
/// track-artist is NEVER an album-artist appears in `tracksDisplay(byArtist:)` but NOT in
/// `albums(byArtist:)` (which filters `album_artist_id`). Built in its own temp store so
/// the shared `seedFixtureLibrary` (50+ checks assert its exact counts) is untouched.
private func pinByArtistLensSplit(baseURL: URL, number: Int) async throws -> Bool {
    let adHocURL = baseURL.deletingLastPathComponent()
        .appendingPathComponent("br2-asym-\(UUID().uuidString).sqlite3")
    defer { cleanupStore(adHocURL) }
    let store = try await LibraryStore(url: adHocURL, appBuild: "verify")
    let root = try await store.addRoot(URL(fileURLWithPath: "/AdHoc"))
    let gen = try await store.beginScanGeneration()
    let ids = try await store.upsert(
        [makeScanned(path: "/AdHoc/guest.flac", name: "guest")], folderID: root, generation: gen
    )
    guard let trackID = ids.first else { printFail(number, "BR2: asym seed failed"); return false }
    try await store.applyMetadata(
        TrackMetadata(title: "Guest Track", artistName: "Guest Star", albumTitle: "Comp Album",
                      albumArtistName: "Host", year: 2019, trackNo: 1, genres: []),
        forTrack: trackID
    )
    guard let guest = try await store.artists().first(where: { $0.name == "Guest Star" }) else {
        printFail(number, "BR2: asym missing Guest Star"); return false
    }
    let lensAlbums = try await store.albums(byArtist: guest.id)
    let lensTracks = try await store.tracksDisplay(byArtist: guest.id).map(\.title)
    guard lensAlbums.isEmpty, lensTracks == ["Guest Track"] else {
        printFail(number, "BR2: byArtist lens split not pinned "
            + "(albums=\(lensAlbums.count), tracks=\(lensTracks))"); return false
    }
    return true
}

// MARK: - BR2b — genre drill-down (track_genres JOIN, no fan-out)

func checkBrowseGenreDrilldown(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let expected = try await seedFixtureLibrary(store)
        // Electronic: a multi-genre track (a2 is Pop+Electronic) must not double-list.
        guard try await checkGenre(store, name: "Electronic", number: number, expected: expected) else {
            return false
        }
        // Pop: an album (Alpha) with TWO Pop tracks must list once (album-level dedup).
        guard try await checkGenre(store, name: "Pop", number: number, expected: expected) else {
            return false
        }
        printPass(number, "BR2b: albums/tracksDisplay(inGenre:) via track_genres JOIN = expected sets; "
            + "no fan-out (a 2-genre track listed once; a 2-track-in-genre album listed once)")
        return true
    } catch {
        printFail(number, "BR2b threw: \(error)"); return false
    }
}

/// Assert one genre's album + track drill-downs match the derived sets with no fan-out.
private func checkGenre(
    _ store: LibraryStore, name: String, number: Int, expected: FixtureExpectations
) async throws -> Bool {
    guard let genre = try await store.genres().first(where: { $0.name == name }) else {
        printFail(number, "BR2b: seed missing genre \(name)"); return false
    }
    let tracks = try await store.tracksDisplay(inGenre: genre.id)
    guard Set(tracks.map(\.title)) == (expected.tracksByGenre[name] ?? []),
          tracks.count == Set(tracks.map(\.id)).count else {
        printFail(number, "BR2b: tracksDisplay(inGenre: \(name)) set/fan-out wrong"); return false
    }
    let albums = try await store.albums(inGenre: genre.id)
    guard Set(albums.map(\.title)) == (expected.albumsByGenre[name] ?? []),
          albums.count == Set(albums.map(\.id)).count else {
        printFail(number, "BR2b: albums(inGenre: \(name)) set/fan-out wrong"); return false
    }
    // The inGenre album trackCount must be the album's FULL count (not the in-genre
    // subset) — a count(DISTINCT) over the genre JOIN would regress this silently.
    for album in albums {
        guard try await store.album(id: album.id)?.trackCount == album.trackCount else {
            printFail(number, "BR2b: albums(inGenre: \(name)) trackCount not the album's FULL count "
                + "(\(album.title))"); return false
        }
    }
    return true
}

// MARK: - BR2c — year facet + albums(inYear:)

func checkBrowseYearFacet(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let expected = try await seedFixtureLibrary(store)
        let years = try await store.years()
        guard years == expected.yearsDescending else {
            printFail(number, "BR2c: years() \(years) != expected \(expected.yearsDescending)"); return false
        }
        for year in years {
            let albums = try await store.albums(inYear: year)
            guard Set(albums.map(\.title)) == (expected.albumsByYear[year] ?? []) else {
                printFail(number, "BR2c: albums(inYear: \(year)) set != expected"); return false
            }
            guard albums.allSatisfy({ $0.year == year }) else {
                printFail(number, "BR2c: albums(inYear: \(year)) returned an off-year album"); return false
            }
        }
        guard try await checkYearFacetsAndTracks(store, expected: expected, number: number) else {
            return false
        }
        printPass(number, "BR2c: years() = distinct non-null track years descending \(years); "
            + "albums(inYear:) that year's albums; yearFacets()/tracksDisplay(inYear:) counts + sets match")
        return true
    } catch {
        printFail(number, "BR2c threw: \(error)"); return false
    }
}

/// `yearFacets()` counts + `tracksDisplay(inYear:)` sets/order/no-fan-out, all TRACK-year
/// (`tracks.year`). The list count (`YearFacet.trackCount`) must equal the detail length and
/// the derived fixture count; the facet year order must equal `years()`; and the counts must
/// sum to every non-null-year track.
private func checkYearFacetsAndTracks(
    _ store: LibraryStore, expected: FixtureExpectations, number: Int
) async throws -> Bool {
    let facets = try await store.yearFacets()
    guard facets.map(\.year) == expected.yearsDescending else {
        printFail(number, "BR2c: yearFacets() years \(facets.map(\.year)) != years() descending")
        return false
    }
    for facet in facets {
        let tracks = try await store.tracksDisplay(inYear: facet.year)
        let albumIDs = tracks.compactMap { $0.albumID.map(Int.init) }
        guard Set(tracks.map(\.title)) == (expected.tracksByYear[facet.year] ?? []),
              tracks.count == Set(tracks.map(\.id)).count else {
            printFail(number, "BR2c: tracksDisplay(inYear: \(facet.year)) set/fan-out wrong"); return false
        }
        guard albumIDs.count == tracks.count, isNonDecreasing(albumIDs),
              tracks.allSatisfy({ $0.year == facet.year }) else {
            printFail(number, "BR2c: tracksDisplay(inYear: \(facet.year)) order/off-year wrong"); return false
        }
        guard facet.trackCount == tracks.count,
              facet.trackCount == (expected.yearTrackCounts[facet.year] ?? -1) else {
            printFail(number, "BR2c: yearFacet(\(facet.year)) count \(facet.trackCount) != "
                + "detail/fixture"); return false
        }
    }
    let facetSum = facets.reduce(0) { $0 + $1.trackCount }
    guard facetSum == expected.yearTrackCounts.values.reduce(0, +) else {
        printFail(number, "BR2c: sum(yearFacet counts) \(facetSum) != non-null-year total"); return false
    }
    return true
}

// MARK: - BR3 — single-facet reads equal the list entry

func checkBrowseSingleFacet(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        _ = try await seedFixtureLibrary(store)
        for album in try await store.albums(sortedBy: .title) {
            guard try await store.album(id: album.id) == album else {
                printFail(number, "BR3: album(id: \(album.id)) != its list entry"); return false
            }
        }
        for artist in try await store.artists(sortedBy: .title) {
            guard try await store.artist(id: artist.id) == artist else {
                printFail(number, "BR3: artist(id: \(artist.id)) != its list entry"); return false
            }
        }
        for genre in try await store.genres() {
            guard try await store.genre(id: genre.id) == genre else {
                printFail(number, "BR3: genre(id: \(genre.id)) != its list entry"); return false
            }
        }
        guard try await store.album(id: 999_999) == nil, try await store.artist(id: 999_999) == nil,
              try await store.genre(id: 999_999) == nil else {
            printFail(number, "BR3: a nonexistent id did not resolve to nil"); return false
        }
        printPass(number, "BR3: album(id:)/artist(id:)/genre(id:) each equal the matching list entry "
            + "(shared builder); a nonexistent id → nil")
        return true
    } catch {
        printFail(number, "BR3 threw: \(error)"); return false
    }
}

// MARK: - BR3b — id-0 unknown-artist sentinel is never surfaced

func checkBrowseSentinelExcluded(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        _ = try await seedFixtureLibrary(store)
        guard try await store.artist(id: unknownArtistID) == nil else {
            printFail(number, "BR3b: artist(id: sentinel) surfaced the id-0 unknown-artist row"); return false
        }
        let artists = try await store.artists()
        guard !artists.contains(where: { $0.id == unknownArtistID }) else {
            printFail(number, "BR3b: the id-0 sentinel leaked into artists()"); return false
        }
        printPass(number, "BR3b: no artist read surfaces the id-0 unknown-artist sentinel "
            + "(artist(id: 0) == nil; sentinel absent from artists())")
        return true
    } catch {
        printFail(number, "BR3b threw: \(error)"); return false
    }
}

// MARK: - BR4 — pagination window (no dup/gap; nil == unbounded)

func checkBrowsePagination(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        _ = try await seedFixtureLibrary(store)
        guard try await checkDisplayPagination(store, number: number) else { return false }
        guard try await checkAlbumPagination(store, number: number) else { return false }
        // allTracks (the LibraryTrack read) also honours nil == unbounded.
        let unbounded = try await store.allTracks(sortedBy: .name).map(\.id)
        guard try await store.allTracks(sortedBy: .name, limit: nil, offset: 0).map(\.id) == unbounded else {
            printFail(number, "BR4: allTracks limit:nil != unbounded"); return false
        }
        printPass(number, "BR4: adjacent limit/offset pages have no dupes/gaps under a fixed sort "
            + "(allTracksDisplay + albums); limit == nil reproduces the unbounded result exactly")
        return true
    } catch {
        printFail(number, "BR4 threw: \(error)"); return false
    }
}

/// Two adjacent Display pages tile the unbounded prefix exactly; nil == unbounded.
private func checkDisplayPagination(_ store: LibraryStore, number: Int) async throws -> Bool {
    let all = try await store.allTracksDisplay(sortedBy: .name).map(\.id)
    let size = 5
    let page1 = try await store.allTracksDisplay(sortedBy: .name, limit: size, offset: 0).map(\.id)
    let page2 = try await store.allTracksDisplay(sortedBy: .name, limit: size, offset: size).map(\.id)
    let window = page1 + page2
    guard window.count == min(size * 2, all.count), window == Array(all.prefix(window.count)),
          Set(window).count == window.count else {
        printFail(number, "BR4: Display pages have a dup/gap vs the unbounded prefix"); return false
    }
    guard try await store.allTracksDisplay(sortedBy: .name, limit: nil).map(\.id) == all else {
        printFail(number, "BR4: allTracksDisplay limit:nil != unbounded"); return false
    }
    return true
}

/// Two adjacent album pages tile the unbounded prefix exactly; nil == unbounded.
private func checkAlbumPagination(_ store: LibraryStore, number: Int) async throws -> Bool {
    let all = try await store.albums(sortedBy: .title).map(\.id)
    let size = 4
    let page1 = try await store.albums(sortedBy: .title, limit: size, offset: 0).map(\.id)
    let page2 = try await store.albums(sortedBy: .title, limit: size, offset: size).map(\.id)
    let window = page1 + page2
    guard window.count == min(size * 2, all.count), window == Array(all.prefix(window.count)),
          Set(window).count == window.count else {
        printFail(number, "BR4: album pages have a dup/gap vs the unbounded prefix"); return false
    }
    guard try await store.albums(sortedBy: .title, limit: nil).map(\.id) == all else {
        printFail(number, "BR4: albums limit:nil != unbounded"); return false
    }
    return true
}

// MARK: - BR7 — ArtistFacet.trackCount (track-artist lens) + the 0-song album-artist

func checkBrowseArtistCount(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let expected = try await seedFixtureLibrary(store)
        for artist in try await store.artists() {
            let detailCount = try await store.tracksDisplay(byArtist: artist.id).count
            guard artist.trackCount == detailCount,
                  artist.trackCount == (expected.artistTrackCounts[artist.name] ?? 0) else {
                printFail(number, "BR7: artist \(artist.name) count \(artist.trackCount) != "
                    + "tracksDisplay(byArtist:) \(detailCount) / fixture"); return false
            }
        }
        // An album-artist-only artist ("Various Artists", never a track-artist) lists with
        // trackCount 0 and an EMPTY drill-down — the DAO keeps it reachable (the UI hides it).
        guard let va = try await store.artists().first(where: { $0.name == "Various Artists" }) else {
            printFail(number, "BR7: seed missing the Various Artists album-artist"); return false
        }
        guard va.trackCount == 0, try await store.tracksDisplay(byArtist: va.id).isEmpty else {
            printFail(number, "BR7: Various Artists not 0-song/empty (count=\(va.trackCount))"); return false
        }
        printPass(number, "BR7: ArtistFacet.trackCount == tracksDisplay(byArtist:).count == fixture "
            + "(track-artist lens); an album-artist-only artist lists with 0 songs + empty drill-down")
        return true
    } catch {
        printFail(number, "BR7 threw: \(error)"); return false
    }
}

// MARK: - BR8 — null-year omission + 0-song genre (ad-hoc store, shared fixture untouched)

func checkBrowseYearNullAndEmptyGenre(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/AdHoc"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            [makeScanned(path: "/AdHoc/dated.flac", name: "dated"),
             makeScanned(path: "/AdHoc/yearless.flac", name: "yearless")],
            folderID: root, generation: gen
        )
        guard ids.count == 2 else { printFail(number, "BR8: ad-hoc seed failed"); return false }
        // Dated: year 2021, genre "Ghost" (orphaned below). Yearless: year nil, genre "Keep".
        try await store.applyMetadata(
            TrackMetadata(title: "Dated", artistName: "AH", albumTitle: "AH Album",
                          albumArtistName: "AH", year: 2021, trackNo: 1, genres: ["Ghost"]),
            forTrack: ids[0]
        )
        try await store.applyMetadata(
            TrackMetadata(title: "Yearless", artistName: "AH", albumTitle: "AH Album",
                          albumArtistName: "AH", year: nil, trackNo: 2, genres: ["Keep"]),
            forTrack: ids[1]
        )
        // Orphan "Ghost": re-tag Dated to drop it → a genre row with 0 tracks remains.
        try await store.applyMetadata(
            TrackMetadata(title: "Dated", artistName: "AH", albumTitle: "AH Album",
                          albumArtistName: "AH", year: 2021, trackNo: 1, genres: []),
            forTrack: ids[0]
        )
        guard try await checkNullYearOmitted(store, number: number),
              try await checkZeroSongGenre(store, number: number) else { return false }
        printPass(number, "BR8: a null-year track is absent from years()/yearFacets()/tracksDisplay(inYear:)"
            + " yet present in allTracksDisplay; a 0-song genre lists with count 0 + empty drill-down")
        return true
    } catch {
        printFail(number, "BR8 threw: \(error)"); return false
    }
}

/// The null-year track is omitted from every year read but present in the full list.
private func checkNullYearOmitted(_ store: LibraryStore, number: Int) async throws -> Bool {
    let years = try await store.years()
    let facets = try await store.yearFacets()
    guard years == [2021], facets.map(\.year) == [2021], facets.first?.trackCount == 1 else {
        printFail(number, "BR8: null-year leaked into years()/yearFacets() (\(years))"); return false
    }
    guard try await store.tracksDisplay(inYear: 2021).map(\.title) == ["Dated"] else {
        printFail(number, "BR8: tracksDisplay(inYear:2021) != [Dated]"); return false
    }
    guard try Set(await store.allTracksDisplay().map(\.title)) == ["Dated", "Yearless"] else {
        printFail(number, "BR8: the yearless track is missing from allTracksDisplay"); return false
    }
    return true
}

/// The orphaned genre lists with count 0 and an empty drill-down; a live genre still counts.
private func checkZeroSongGenre(_ store: LibraryStore, number: Int) async throws -> Bool {
    let genres = try await store.genres()
    guard let ghost = genres.first(where: { $0.name == "Ghost" }) else {
        printFail(number, "BR8: orphaned genre Ghost not listed"); return false
    }
    guard ghost.trackCount == 0, try await store.tracksDisplay(inGenre: ghost.id).isEmpty,
          try await store.genre(id: ghost.id) == ghost else {
        printFail(number, "BR8: Ghost not 0-song/empty (count=\(ghost.trackCount))"); return false
    }
    guard genres.first(where: { $0.name == "Keep" })?.trackCount == 1 else {
        printFail(number, "BR8: live genre Keep count != 1"); return false
    }
    return true
}
