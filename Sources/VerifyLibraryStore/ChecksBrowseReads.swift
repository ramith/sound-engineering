// ChecksBrowseReads — S9.1 browse/search DAO reads (design §3, test plan §10).
//
// Drives the REAL LibraryStore on a REAL temp store built from `seedFixtureLibrary`,
// asserting the S9.1 read additions against DERIVED `FixtureExpectations` sets (never
// magic numbers). Same VerifyAUGraph idiom (Bool return, one numbered PASS line each):
//   BR1  artwork-path batched map (hash→cache_path) + on-disk thumbnail convention.
//   BR1b a key with no artwork row is ABSENT from the map (no throw); others resolve.
//   BR1c a key set > 999 is chunked and returns the full correct map.
//   BR2  albums/tracksDisplay(byArtist:) sets + order + resolved artist/album names.
//   BR2b albums/tracksDisplay(inGenre:) sets via track_genres JOIN, no fan-out.
//   BR2c years() distinct-desc + albums(inYear:) that year's albums.
//   BR3  album(id:)/artist(id:) equal the matching list entry.
//   BR3b artist reads never surface the id-0 unknown-artist sentinel.
//   BR4  pagination window: adjacent pages no dup/gap; limit == nil == unbounded.
//   BR5  EXPLAIN QUERY PLAN of the hot reads: USING INDEX, never SCAN TABLE tracks.

import CoreGraphics
import Foundation
import ImageIO
import LibraryScan
import LibraryStore

// MARK: - BR1 — artwork-path batched map + on-disk thumbnail convention

func checkBrowseArtworkMap(number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("br-artwork-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        guard let png = makeSolidPNG(width: 400, height: 400) else {
            printFail(number, "BR1: could not synthesize a test PNG"); return false
        }
        let link = try cache.store(imageData: png, uti: "public.png")
        try await store.linkArtwork(
            contentHash: link.contentHash, cachePath: link.cachePath,
            size: link.pixelSize, byteSize: link.byteSize
        )
        let map = try await store.artworkCachePaths(forKeys: [link.contentHash])
        guard let resolved = map[link.contentHash], resolved == link.cachePath, map.count == 1 else {
            printFail(number, "BR1: batched map did not return the exact hash→cache_path"); return false
        }
        // Derive the thumbnail path the same way S9 will, and assert on-disk convention.
        let thumbPath = ArtworkCache.thumbnailPath(forOriginal: resolved)
        guard thumbPath.hasSuffix(".thumb.jpg"), FileManager.default.fileExists(atPath: thumbPath) else {
            printFail(number, "BR1: derived thumbnail path off-convention or missing on disk"); return false
        }
        // The single-key convenience wraps the batched form.
        guard try await store.artworkCachePath(forKey: link.contentHash) == link.cachePath else {
            printFail(number, "BR1: single-key convenience disagreed with the batched map"); return false
        }
        printPass(number, "BR1: artworkCachePaths returns the exact hash→cache_path map; the derived "
            + ".thumb.jpg thumbnail exists on disk (ArtworkCache.thumbnailPath convention)")
        return true
    } catch {
        printFail(number, "BR1 threw: \(error)"); return false
    }
}

// MARK: - BR1b — cache-miss key is absent (no throw)

func checkBrowseArtworkMiss(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        try await store.linkArtwork(contentHash: "hash-present", cachePath: "/cache/present.jpg",
                                    size: .zero, byteSize: 100)
        let map = try await store.artworkCachePaths(forKeys: ["hash-present", "hash-absent"])
        guard map["hash-present"] == "/cache/present.jpg" else {
            printFail(number, "BR1b: present key did not resolve"); return false
        }
        guard map["hash-absent"] == nil, map.count == 1 else {
            printFail(number, "BR1b: a key with no artwork row leaked into the map"); return false
        }
        guard try await store.artworkCachePath(forKey: "hash-absent") == nil else {
            printFail(number, "BR1b: single-key convenience did not return nil for a miss"); return false
        }
        printPass(number, "BR1b: a key with no artwork row is simply ABSENT from the map (no throw); "
            + "present keys resolve")
        return true
    } catch {
        printFail(number, "BR1b threw: \(error)"); return false
    }
}

// MARK: - BR1c — IN-list chunking (> 999 keys)

func checkBrowseArtworkChunking(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // > 999 synthetic artwork rows → forces multiple IN-list chunks.
        let count = 1100
        let keys = (0 ..< count).map { "synth-hash-\($0)" }
        for (index, key) in keys.enumerated() {
            try await store.linkArtwork(contentHash: key, cachePath: "/cache/\(key).jpg",
                                        size: .zero, byteSize: Int64(index))
        }
        // Query all keys PLUS one miss, in one call — must chunk and return the full map.
        let map = try await store.artworkCachePaths(forKeys: keys + ["not-a-hash"])
        guard map.count == count else {
            printFail(number, "BR1c: chunked map has \(map.count) entries, expected \(count)"); return false
        }
        for key in keys where map[key] != "/cache/\(key).jpg" {
            printFail(number, "BR1c: chunked map wrong/missing value for \(key)"); return false
        }
        guard map["not-a-hash"] == nil else {
            printFail(number, "BR1c: the miss leaked into the chunked map"); return false
        }
        printPass(number, "BR1c: a \(count)-key IN-list is chunked (limit 32766) and returns the full "
            + "correct hash→cache_path map; the miss stays absent")
        return true
    } catch {
        printFail(number, "BR1c threw: \(error)"); return false
    }
}

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
        printPass(number, "BR2c: years() = distinct non-null track years descending \(years); "
            + "albums(inYear:) returns exactly that year's albums")
        return true
    } catch {
        printFail(number, "BR2c threw: \(error)"); return false
    }
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
        guard try await store.album(id: 999_999) == nil, try await store.artist(id: 999_999) == nil else {
            printFail(number, "BR3: a nonexistent id did not resolve to nil"); return false
        }
        printPass(number, "BR3: album(id:)/artist(id:) each equal the matching list entry "
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

// MARK: - BR5 — EXPLAIN QUERY PLAN: index-driven, never SCAN TABLE tracks

func checkBrowseQueryPlan(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        _ = try await seedFixtureLibrary(store)
        // BR5 is a PORTABLE plan tripwire: it holds because NO `ANALYZE` / `sqlite_stat1` /
        // `PRAGMA optimize` is ever run, so the planner picks indexes from the schema (not
        // row-count stats) even on this tiny fixture — the store runs none of those.
        let targets: [(LibraryStore.HotRead, String)] = [
            (.tracksDisplayByArtist, "tracksDisplay(byArtist:)"),
            (.tracksDisplayInAlbum, "tracksDisplay(inAlbum:)"),
            (.tracksDisplayInGenre, "tracksDisplay(inGenre:)"),
            (.albumsInYear, "albums(inYear:)"),
            (.albumsInGenre, "albums(inGenre:)"),
        ]
        for (target, label) in targets {
            let details = try await store.explainQueryPlan(for: target)
            guard details.contains(where: detailUsesIndex) else {
                printFail(number, "BR5: \(label) plan has no USING INDEX: \(details)"); return false
            }
            guard !details.contains(where: detailIsTracksTableScan) else {
                printFail(number, "BR5: \(label) SCANs the tracks table: \(details)"); return false
            }
        }
        printPass(number, "BR5: EXPLAIN QUERY PLAN for tracksDisplay(byArtist:/inAlbum:/inGenre:) + "
            + "albums(inYear:/inGenre:) is SEARCH … USING INDEX — never SCAN TABLE tracks (aliases t/t2)")
        return true
    } catch {
        printFail(number, "BR5 threw: \(error)"); return false
    }
}

// MARK: - EXPLAIN plan parsing helpers

/// True if a plan `detail` row is an index-driven access (SEARCH … USING [COVERING] INDEX).
/// Internal (not private) so the S9.5 Songs-sort plan check reuses the SAME definition.
func detailUsesIndex(_ detail: String) -> Bool {
    let upper = detail.uppercased()
    return upper.contains("USING INDEX") || upper.contains("USING COVERING INDEX")
}

/// True if a plan `detail` row is a FULL SCAN of the `tracks` table — the tripwire. An
/// index SCAN (`SCAN t USING [COVERING] INDEX …`) is fine; a legacy `SCAN TABLE tracks`
/// is also caught. `tracks` appears as alias `t` in the display reads and `t2` inside
/// `albums(inGenre:)`'s membership sub-select — flag BOTH, else a `SCAN t2` slips through
/// and the genre coverage is illusory. Internal (not private) so the S9.5 Songs-sort plan
/// check reuses the SAME tripwire definition (one source of truth, no drift).
func detailIsTracksTableScan(_ detail: String) -> Bool {
    let upper = detail.uppercased()
    guard upper.hasPrefix("SCAN"), !detailUsesIndex(detail) else { return false }
    var tokens = upper.split(separator: " ").map(String.init)
    tokens.removeFirst() // drop "SCAN"
    if tokens.first == "TABLE" { tokens.removeFirst() } // legacy "SCAN TABLE tracks"
    guard let target = tokens.first else { return false }
    return ["T", "T2", "TRACKS"].contains(target)
}

// MARK: - Synthetic image helper (CoreGraphics/ImageIO)

/// A solid-color RGBA PNG of the given size, or nil if CoreGraphics is unavailable.
private func makeSolidPNG(width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo
    ) else { return nil }
    context.setFillColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { return nil }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, "public.png" as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}
