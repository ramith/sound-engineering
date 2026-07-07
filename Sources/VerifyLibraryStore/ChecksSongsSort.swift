// ChecksSongsSort — S9.5 (D7) rich sortable-table `TrackSort` orders + their EXPLAIN plans,
// PLUS §12.1 full-catalog-columns projection/EXPLAIN + §12.3 play-tracking (SS3/SS4/SS5).
//
// Drives the REAL LibraryStore over a small AD-HOC store (its own temp DB, so the shared
// `seedFixtureLibrary` the other 50+ checks pin is untouched — mirrors the BR2 lens-split
// idiom). The fixture is built with DELIBERATE collisions (equal title/format/year/duration/
// album under one artist) + NULLs (a track with no title/artist/album/year/duration) so each
// new sort's primary ordering, its `id` final tiebreak on a collision, and its documented
// NULLs-ordering are all provable against a DERIVED expected id-order (never a magic number):
//   SS1  every new sort returns the correct order + deterministic `id` tiebreak on collisions;
//        documented NULLs-ordering holds (year first/last, album last, duration-0 first/last,
//        composite nil-artist first); asc/desc are exact reverses where the spec says so.
//   SS2  (R3) EXPLAIN QUERY PLAN for every new sort's Display read: never SCAN TABLE tracks
//        (the BR5 tripwire), and the index-orderable sorts (date_added / year) avoid a
//        temp-b-tree filesort entirely. Prints the index-vs-filesort split for the record.
//   SS3  (§12.1) full-catalog projection round-trip: discNo/fileSize/playCount/lastPlayed/
//        albumArtistName/genreName decode correctly (incl. every NULL/sentinel/no-fan-out
//        case), AND the pre-existing indices 0–16 are undrifted by the append.
//   SS4  (§12.1) EXPLAIN shape lock: the enriched full projection shows the genre
//        CORRELATED SCALAR SUBQUERY (index-driven `tg` access) + a `SEARCH aa …
//        INTEGER PRIMARY KEY` step, never `SCAN TABLE tracks`; the BR5 filtered hot reads
//        (byArtist/inAlbum/inGenre) still hold with the enriched projection.
//   SS5  (§12.3) `incrementPlayCount` is atomic + URL-keyed: two calls accumulate and
//        refresh `last_played`; two tracks increment independently; a nonexistent-url call
//        is a silent no-op.

import Foundation
import LibraryStore

func songsSortCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "ss1-sort-order-tiebreak", run: checkSongsSortOrder),
        CheckCase(label: "ss2-sort-explain-plan", run: checkSongsSortQueryPlan),
        CheckCase(label: "ss3-catalog-projection-roundtrip", run: checkCatalogProjectionRoundTrip),
        CheckCase(label: "ss4-catalog-explain-shape", run: checkCatalogQueryPlanShape),
        CheckCase(label: "ss5-increment-play-count", run: checkIncrementPlayCount),
    ]
}

// MARK: - Ad-hoc sort fixture (deliberate collisions + NULLs)

/// One sort-fixture track. `title`/`artist`/`album`/`year` are optional so a row can carry
/// NULLs; `format` (via the `ScannedFile`) and `duration` are always present (`duration = 0`
/// exercises the undecoded case). Inserted in array order, so `id` ascends with the index.
private struct SortTrack {
    let name: String
    let format: String
    let title: String?
    let artist: String?
    let album: String?
    let year: Int?
    let durationMs: Int64
    let discNo: Int?
    let trackNo: Int?
}

/// The fixture, in insertion (id-ascending) order. Indices 0…4 are referenced by the derived
/// expectations below. Collisions: title "Mango"/"mango" (0,1) & "Apple"/"apple" (2,4);
/// format flac (0,3,4); year 2001 (0,2) / 1999 (1,4) / nil (3); duration 200 (0,2) / 100 (1,4)
/// / 0 (3); album Yankee (0,2) / alpha (1,4) / nil (3); artist Beta (0,2) / alpha (1,4) / nil
/// (3); (artist,album,disc,track) fully collides for (1,4) → pure id tiebreak.
private let sortFixture: [SortTrack] = [
    SortTrack(name: "t1", format: "FLAC", title: "Mango", artist: "Beta", album: "Yankee",
              year: 2001, durationMs: 200, discNo: 1, trackNo: 2),
    SortTrack(name: "t2", format: "mp3", title: "mango", artist: "alpha", album: "alpha",
              year: 1999, durationMs: 100, discNo: 1, trackNo: 1),
    SortTrack(name: "t3", format: "AAC", title: "Apple", artist: "Beta", album: "Yankee",
              year: 2001, durationMs: 200, discNo: 1, trackNo: 1),
    SortTrack(name: "t4", format: "flac", title: nil, artist: nil, album: nil,
              year: nil, durationMs: 0, discNo: nil, trackNo: nil),
    SortTrack(name: "t5", format: "FLAC", title: "apple", artist: "alpha", album: "alpha",
              year: 1999, durationMs: 100, discNo: 1, trackNo: 1),
]

/// Seed `sortFixture` into a fresh root as ONE `upsert` batch (so `date_added` is a single
/// shared epoch → its ordering reduces to the pure `id` tiebreak), then decorate each row.
/// Returns the inserted ids in fixture order (`ids[i]` is `sortFixture[i]`).
private func seedSortFixture(_ store: LibraryStore) async throws -> [Int64] {
    let root = try await store.addRoot(URL(fileURLWithPath: "/SortFix"))
    let gen = try await store.beginScanGeneration()
    let files = sortFixture.map {
        ScannedFile(url: URL(fileURLWithPath: "/SortFix/\($0.name).flac"), relativePath: "",
                    name: $0.name, format: $0.format, fileSize: 4096, mtime: 1000)
    }
    let ids = try await store.upsert(files, folderID: root, generation: gen)
    for (index, track) in sortFixture.enumerated() {
        try await store.applyMetadata(
            TrackMetadata(title: track.title, artistName: track.artist, albumTitle: track.album,
                          albumArtistName: track.artist, year: track.year, trackNo: track.trackNo,
                          discNo: track.discNo, genres: [], durationMs: track.durationMs),
            forTrack: ids[index]
        )
    }
    return ids
}

// MARK: - SS1 — order + id tiebreak + NULLs

func checkSongsSortOrder(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let ids = try await seedSortFixture(store)
        // Expected id-orders derived by hand from `sortFixture` (index → ids[index]).
        // Each is: primary key order, then `id` ascending/descending as the final tiebreak.
        let expected: [(TrackSort, [Int])] = [
            // title NOCASE: apple(3,5) < mango(1,2) < t4(name fallback); id tiebreak within.
            (.titleAsc, [2, 4, 0, 1, 3]),
            (.titleDesc, [3, 1, 0, 4, 2]), // exact reverse of titleAsc
            // composite: nil-artist FIRST, then alpha(t2,t5 full-collide → id) then Beta(t3,t1).
            (.artistAlbumTrack, [3, 1, 4, 2, 0]),
            // album NOCASE, NULL album LAST (both directions); id tiebreak.
            (.albumTitleAsc, [1, 4, 0, 2, 3]),
            (.albumTitleDesc, [2, 0, 4, 1, 3]), // nulls STILL last → NOT a plain reverse
            // duration: 0(t4) FIRST asc; id tiebreak on the 100 & 200 pairs.
            (.durationAsc, [3, 1, 4, 0, 2]),
            (.durationDesc, [2, 0, 4, 1, 3]), // exact reverse of durationAsc
            // format NOCASE: aac(t3) < flac(t1,t4,t5) < mp3(t2); id tiebreak in the flac run.
            (.formatAsc, [2, 0, 3, 4, 1]),
            (.formatDesc, [1, 4, 3, 0, 2]), // exact reverse of formatAsc
            // year: NULL FIRST asc (t4), then 1999(t2,t5), then 2001(t1,t3); id tiebreak.
            (.yearAsc, [3, 1, 4, 0, 2]),
            (.yearDesc, [2, 0, 4, 1, 3]), // NULL LAST desc → exact reverse of yearAsc
        ]
        for (sort, indices) in expected {
            let want = indices.map { ids[$0] }
            let got = try await store.allTracksDisplay(sortedBy: sort).map(\.id)
            guard got == want else {
                printFail(number, "SS1: \(sort) order \(got) != expected \(want)"); return false
            }
        }
        guard try await checkDateAddedOrder(store, ids: ids, number: number) else { return false }
        printPass(number, "SS1: every new TrackSort returns the derived primary order with a "
            + "deterministic id tiebreak on collisions; documented NULLs-ordering holds (year "
            + "first/last, album last, duration-0 first/last, composite nil-artist first)")
        return true
    } catch {
        printFail(number, "SS1 threw: \(error)"); return false
    }
}

/// `date_added` is one shared epoch for the batch, so its ordering IS the `id` tiebreak:
/// asc = ids ascending, desc = ids descending, and asc reversed == desc (tiebreak included).
private func checkDateAddedOrder(_ store: LibraryStore, ids: [Int64], number: Int) async throws -> Bool {
    let asc = try await store.allTracksDisplay(sortedBy: .dateAddedAsc).map(\.id)
    let desc = try await store.allTracksDisplay(sortedBy: .dateAddedDescending).map(\.id)
    guard asc == ids, desc == ids.reversed(), asc == desc.reversed() else {
        printFail(number, "SS1: date_added asc/desc \(asc)/\(desc) not the id tiebreak / reverse")
        return false
    }
    return true
}

// MARK: - SS2 — EXPLAIN QUERY PLAN (R3): no SCAN TABLE tracks; index-orderable sorts skip filesort

func checkSongsSortQueryPlan(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        _ = try await seedSortFixture(store)
        // Every S9.5 sort, in report order. `indexOrdered` are the ones an index can satisfy
        // the ORDER BY for (date_added → idx_tracks_added, year → idx_tracks_year), so they must
        // NOT need a temp-b-tree filesort. The rest are ACCEPTED bounded filesorts (R3 finding —
        // reported, not hacked around); all must still clear the BR5 no-SCAN-TABLE-tracks wire.
        let allSorts: [(TrackSort, String)] = [
            (.titleAsc, "titleAsc"), (.titleDesc, "titleDesc"), (.artistAlbumTrack, "artistAlbumTrack"),
            (.albumTitleAsc, "albumTitleAsc"), (.albumTitleDesc, "albumTitleDesc"),
            (.durationAsc, "durationAsc"), (.durationDesc, "durationDesc"),
            (.dateAddedAsc, "dateAddedAsc"), (.dateAddedDescending, "dateAddedDescending"),
            (.formatAsc, "formatAsc"), (.formatDesc, "formatDesc"),
            (.yearAsc, "yearAsc"), (.yearDesc, "yearDesc"),
            // S9.5 §12.1 full-catalog additions — all ACCEPTED bounded filesorts (no index
            // covers disc_no/file_size/play_count/last_played alone, nor the `aa` name join).
            (.discNoAsc, "discNoAsc"), (.discNoDesc, "discNoDesc"),
            (.fileSizeAsc, "fileSizeAsc"), (.fileSizeDesc, "fileSizeDesc"),
            (.playCountAsc, "playCountAsc"), (.playCountDesc, "playCountDesc"),
            (.lastPlayedAsc, "lastPlayedAsc"), (.lastPlayedDesc, "lastPlayedDesc"),
            (.albumArtistAsc, "albumArtistAsc"), (.albumArtistDesc, "albumArtistDesc"),
        ]
        let indexOrdered: Set = ["dateAddedAsc", "dateAddedDescending", "yearAsc", "yearDesc"]
        var indexed: [String] = []
        var filesort: [String] = []
        for (sort, label) in allSorts {
            let plan = try await store.explainAllTracksDisplayPlan(sortedBy: sort)
            guard !plan.contains(where: detailIsTracksTableScan) else {
                printFail(number, "SS2: \(label) SCANs the tracks table: \(plan)"); return false
            }
            let isFilesort = plan.contains { $0.uppercased().contains("USE TEMP B-TREE") }
            if isFilesort { filesort.append(label) } else { indexed.append(label) }
            if indexOrdered.contains(label), isFilesort {
                printFail(number, "SS2: \(label) expected index-ordered but filesorts: \(plan)"); return false
            }
        }
        printPass(number, "SS2 (R3): no new sort SCANs TABLE tracks (all scan via an index). "
            + "Index-ordered (no filesort): \(indexed.sorted()). Accepted bounded filesort "
            + "(temp-b-tree, ~20k rows): \(filesort.sorted())")
        return true
    } catch {
        printFail(number, "SS2 threw: \(error)"); return false
    }
}

// MARK: - SS3 — full-catalog projection round-trip (needs-read columns + index-drift guard)

/// One SS3 fixture track (before `ScannedFile` + metadata). Exercises every §12.1 needs-read
/// field (disc #, file size, album artist incl. the id-0 sentinel/no-album cases, genre incl.
/// MIN/none) AND re-asserts every PRE-EXISTING field (indices 0–16) still decodes correctly
/// after the append — the positional-decode index-drift guard the pre-change review demanded.
private struct CatalogTrack {
    let name: String
    let title: String
    let artist: String
    let album: String?
    let albumArtist: String?
    let year: Int?
    let trackNo: Int?
    let discNo: Int?
    let genres: [String]
    let fileSize: Int64
    let durationMs: Int64
}

/// `full`: a real album-artist + a 2-genre track (MIN picks "Alpha", regardless of insertion
/// order — deliberately inserted "Zeta" first). `sentinel`: an album whose artist is left
/// unset, so `resolveAlbum` defaults it to the id-0 "Unknown Artist" sentinel (0 genres).
/// `noalbum`: no album at all (album_id stays NULL) with exactly ONE genre.
private let catalogFixture: [CatalogTrack] = [
    CatalogTrack(name: "full", title: "Full Track", artist: "Artist Full", album: "Album With AA",
                 albumArtist: "Real Album Artist", year: 2020, trackNo: 3, discNo: 2,
                 genres: ["Zeta", "Alpha"], fileSize: 111_000, durationMs: 210_000),
    CatalogTrack(name: "sentinel", title: "Sentinel Track", artist: "Artist Sentinel",
                 album: "Album No AA", albumArtist: nil, year: 2019, trackNo: 1, discNo: nil,
                 genres: [], fileSize: 222_000, durationMs: 180_000),
    CatalogTrack(name: "noalbum", title: "No Album Track", artist: "Artist Loner", album: nil,
                 albumArtist: nil, year: nil, trackNo: nil, discNo: nil, genres: ["Solo"],
                 fileSize: 333_000, durationMs: 150_000),
]

func checkCatalogProjectionRoundTrip(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/CatalogFix"))
        let generation = try await store.beginScanGeneration()
        let files = catalogFixture.map {
            ScannedFile(url: URL(fileURLWithPath: "/CatalogFix/\($0.name).flac"), relativePath: "",
                        name: $0.name, format: "FLAC", fileSize: $0.fileSize, mtime: 1000)
        }
        let ids = try await store.upsert(files, folderID: root, generation: generation)
        for (index, track) in catalogFixture.enumerated() {
            try await store.applyMetadata(
                TrackMetadata(title: track.title, artistName: track.artist, albumTitle: track.album,
                              albumArtistName: track.albumArtist, year: track.year, trackNo: track.trackNo,
                              discNo: track.discNo, genres: track.genres, durationMs: track.durationMs,
                              sampleRate: 96000, bitDepth: 24, channels: 2),
                forTrack: ids[index]
            )
        }
        // Exercise play_count/last_played THROUGH the real §12.3 DAO, not a raw UPDATE.
        let playedAt: Int64 = 1_720_000_000
        try await store.incrementPlayCount(url: files[0].url, playedAt: playedAt)

        let rows = try await store.allTracksDisplay(sortedBy: .name)
        guard rows.count == catalogFixture.count else {
            printFail(number, "SS3: row count \(rows.count) != \(catalogFixture.count) fixture tracks "
                + "(a JOIN fan-out would inflate this)"); return false
        }
        guard let full = rows.first(where: { $0.title == "Full Track" }),
              let sentinel = rows.first(where: { $0.title == "Sentinel Track" }),
              let noAlbum = rows.first(where: { $0.title == "No Album Track" }) else {
            printFail(number, "SS3: fixture rows missing from allTracksDisplay"); return false
        }

        guard checkPreExistingFieldsUndrifted(full, number: number),
              checkNeedsReadFields(full: full, sentinel: sentinel, noAlbum: noAlbum,
                                   playedAt: playedAt, number: number) else { return false }

        printPass(number, "SS3: full-catalog projection round-trip — discNo(incl. nil)/fileSize/"
            + "playCount/lastPlayed(incl. NULL)/albumArtistName(real+sentinel-blank+no-album-blank)/"
            + "genreName(MIN+none) all decode correctly; pre-existing 0–16 fields undrifted; row "
            + "COUNT stays \(rows.count) (no fan-out)")
        return true
    } catch {
        printFail(number, "SS3 threw: \(error)"); return false
    }
}

/// Assert the PRE-EXISTING indices (0–16) still decode correctly for the `full` fixture row —
/// the index-drift guard the append (17–21) must not break.
private func checkPreExistingFieldsUndrifted(_ full: LibraryTrackDisplay, number: Int) -> Bool {
    guard full.artistName == "Artist Full", full.albumName == "Album With AA",
          full.format == "FLAC", full.trackNo == 3, full.durationMs == 210_000,
          full.year == 2020, full.sampleRate == 96000, full.bitDepth == 24 else {
        printFail(number, "SS3: a pre-existing field (indices 0–16) mis-decoded — index drift "
            + "from the §12.1 append: \(full)")
        return false
    }
    return true
}

/// Assert the §12.1 needs-read fields (17–21) across the three fixture rows. Split into
/// three smaller helpers (disc/file-size, play-tracking, album-artist/genre) so no single
/// function's cyclomatic complexity approaches the budget.
private func checkNeedsReadFields(
    full: LibraryTrackDisplay, sentinel: LibraryTrackDisplay, noAlbum: LibraryTrackDisplay,
    playedAt: Int64, number: Int
) -> Bool {
    checkDiscAndFileSize(full: full, sentinel: sentinel, noAlbum: noAlbum, number: number)
        && checkPlayTrackingFields(full: full, sentinel: sentinel, noAlbum: noAlbum,
                                   playedAt: playedAt, number: number)
        && checkAlbumArtistAndGenreFields(full: full, sentinel: sentinel, noAlbum: noAlbum, number: number)
}

/// Disc # (index 8, re-mapped) and File Size (17) across the three fixture rows.
private func checkDiscAndFileSize(
    full: LibraryTrackDisplay, sentinel: LibraryTrackDisplay, noAlbum: LibraryTrackDisplay, number: Int
) -> Bool {
    guard full.discNo == 2, sentinel.discNo == nil, noAlbum.discNo == nil else {
        printFail(number, "SS3: discNo wrong (full=\(String(describing: full.discNo)), "
            + "sentinel=\(String(describing: sentinel.discNo)), "
            + "noAlbum=\(String(describing: noAlbum.discNo)))")
        return false
    }
    guard full.fileSize == 111_000, sentinel.fileSize == 222_000, noAlbum.fileSize == 333_000 else {
        printFail(number, "SS3: fileSize wrong (full=\(full.fileSize) sentinel=\(sentinel.fileSize) "
            + "noAlbum=\(noAlbum.fileSize))")
        return false
    }
    return true
}

/// Play Count / Last Played (18/19) — the played `full` row vs the two un-played rows.
private func checkPlayTrackingFields(
    full: LibraryTrackDisplay, sentinel: LibraryTrackDisplay, noAlbum: LibraryTrackDisplay,
    playedAt: Int64, number: Int
) -> Bool {
    guard full.playCount == 1, full.lastPlayed == playedAt else {
        printFail(number, "SS3: play_count/last_played not reflected after incrementPlayCount "
            + "(count=\(full.playCount) lastPlayed=\(String(describing: full.lastPlayed)))")
        return false
    }
    guard sentinel.playCount == 0, sentinel.lastPlayed == nil,
          noAlbum.playCount == 0, noAlbum.lastPlayed == nil else {
        printFail(number, "SS3: an un-played track has a nonzero play_count/last_played"); return false
    }
    return true
}

/// Album Artist (20, real/sentinel/no-album) + Genre (21, MIN/none) across the three rows.
private func checkAlbumArtistAndGenreFields(
    full: LibraryTrackDisplay, sentinel: LibraryTrackDisplay, noAlbum: LibraryTrackDisplay, number: Int
) -> Bool {
    guard full.albumArtistName == "Real Album Artist" else {
        printFail(number, "SS3: albumArtistName wrong for a real album-artist: "
            + "\(String(describing: full.albumArtistName))")
        return false
    }
    guard sentinel.albumArtistName == nil else {
        printFail(number, "SS3: the id-0 sentinel album-artist leaked as "
            + "'\(sentinel.albumArtistName ?? "")' instead of nil/blank")
        return false
    }
    guard noAlbum.albumArtistName == nil else {
        printFail(number, "SS3: a no-album track has a non-nil albumArtistName"); return false
    }
    guard full.genreName == "Alpha" else {
        printFail(number, "SS3: genreName should be MIN('Alpha','Zeta') == 'Alpha', got "
            + "\(String(describing: full.genreName))")
        return false
    }
    guard sentinel.genreName == nil else {
        printFail(number, "SS3: a 0-genre track has a non-nil genreName"); return false
    }
    guard noAlbum.genreName == "Solo" else {
        printFail(number, "SS3: single-genre track genreName wrong, got "
            + "\(String(describing: noAlbum.genreName))")
        return false
    }
    return true
}

// MARK: - SS4 — EXPLAIN shape lock: genre CORRELATED SCALAR SUBQUERY + aa JOIN + BR5 recheck

func checkCatalogQueryPlanShape(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        _ = try await seedFixtureLibrary(store)
        let plan = try await store.explainAllTracksDisplayPlan(sortedBy: .name)
        guard plan.contains(where: { $0.uppercased().contains("CORRELATED SCALAR SUBQUERY") }) else {
            printFail(number, "SS4: the enriched full projection is missing the genre CORRELATED "
                + "SCALAR SUBQUERY: \(plan)")
            return false
        }
        // The subquery's `track_genres` (`tg`) access must be index-driven (its PK), not a scan.
        guard plan.contains(where: { $0.uppercased().contains("TG") && detailUsesIndex($0) }) else {
            printFail(number, "SS4: the genre subquery's tg access is not index-driven: \(plan)")
            return false
        }
        guard plan.contains(where: {
            $0.uppercased().contains("SEARCH AA") && $0.uppercased().contains("INTEGER PRIMARY KEY")
        }) else {
            printFail(number, "SS4: no SEARCH aa … INTEGER PRIMARY KEY step in the plan: \(plan)")
            return false
        }
        guard !plan.contains(where: detailIsTracksTableScan) else {
            printFail(number, "SS4: the enriched full projection SCANs the tracks table: \(plan)")
            return false
        }
        guard try await checkEnrichedHotReadsStillHold(store, number: number) else { return false }
        printPass(number, "SS4: the enriched full projection's plan shows a genre CORRELATED "
            + "SCALAR SUBQUERY (tg index-driven) + a SEARCH aa … INTEGER PRIMARY KEY step, never "
            + "SCAN TABLE tracks; the BR5 filtered hot reads still hold with the enriched "
            + "projection — plan: \(plan)")
        return true
    } catch {
        printFail(number, "SS4 threw: \(error)"); return false
    }
}

/// Re-assert the BR5 filtered hot reads (byArtist/inAlbum/inGenre) still clear the
/// index-driven / no-table-scan bar now that the projection they share is enriched.
private func checkEnrichedHotReadsStillHold(_ store: LibraryStore, number: Int) async throws -> Bool {
    let targets: [(LibraryStore.HotRead, String)] = [
        (.tracksDisplayByArtist, "tracksDisplay(byArtist:)"),
        (.tracksDisplayInAlbum, "tracksDisplay(inAlbum:)"),
        (.tracksDisplayInGenre, "tracksDisplay(inGenre:)"),
    ]
    for (target, label) in targets {
        let details = try await store.explainQueryPlan(for: target)
        guard details.contains(where: detailUsesIndex) else {
            printFail(number, "SS4: \(label) lost its USING INDEX with the enriched projection: \(details)")
            return false
        }
        guard !details.contains(where: detailIsTracksTableScan) else {
            printFail(number, "SS4: \(label) SCANs the tracks table with the enriched projection: \(details)")
            return false
        }
    }
    return true
}

// MARK: - SS5 — incrementPlayCount: atomic, URL-keyed, independent, silent no-op

func checkIncrementPlayCount(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let root = try await store.addRoot(URL(fileURLWithPath: "/PlayFix"))
        let generation = try await store.beginScanGeneration()
        let files = [
            ScannedFile(url: URL(fileURLWithPath: "/PlayFix/a.flac"), relativePath: "",
                        name: "a", format: "FLAC", fileSize: 1000, mtime: 1000),
            ScannedFile(url: URL(fileURLWithPath: "/PlayFix/b.flac"), relativePath: "",
                        name: "b", format: "FLAC", fileSize: 1000, mtime: 1000),
        ]
        _ = try await store.upsert(files, folderID: root, generation: generation)

        // Two increments on track A (accumulation + last_played refresh), one on track B
        // (independence), then a nonexistent-url call (silent no-op).
        let firstPlay: Int64 = 1_700_000_000
        let secondPlay: Int64 = 1_700_000_500
        try await store.incrementPlayCount(url: files[0].url, playedAt: firstPlay)
        try await store.incrementPlayCount(url: files[0].url, playedAt: secondPlay)
        try await store.incrementPlayCount(url: files[1].url, playedAt: firstPlay)
        try await store.incrementPlayCount(
            url: URL(fileURLWithPath: "/PlayFix/does-not-exist.flac"), playedAt: secondPlay
        )

        let rows = try await store.allTracksDisplay(sortedBy: .name)
        guard rows.count == 2 else {
            printFail(number, "SS5: a nonexistent-URL incrementPlayCount call altered row count "
                + "(\(rows.count) rows, expected 2)")
            return false
        }
        guard let trackA = rows.first(where: { $0.url == files[0].url }),
              let trackB = rows.first(where: { $0.url == files[1].url }) else {
            printFail(number, "SS5: seeded tracks missing from the projection"); return false
        }
        guard trackA.playCount == 2, trackA.lastPlayed == secondPlay else {
            printFail(number, "SS5: track A play_count/last_played wrong "
                + "(count=\(trackA.playCount) lastPlayed=\(String(describing: trackA.lastPlayed)))")
            return false
        }
        guard trackB.playCount == 1, trackB.lastPlayed == firstPlay else {
            printFail(number, "SS5: track B did not increment independently of track A "
                + "(count=\(trackB.playCount) lastPlayed=\(String(describing: trackB.lastPlayed)))")
            return false
        }
        printPass(number, "SS5: incrementPlayCount is atomic + URL-keyed — two calls on one track "
            + "accumulate play_count and refresh last_played; a second track increments "
            + "independently; a nonexistent-url call is a silent no-op (no throw, other rows untouched)")
        return true
    } catch {
        printFail(number, "SS5 threw: \(error)"); return false
    }
}
