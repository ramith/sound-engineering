// ChecksSongsSort — S9.5 (D7) rich sortable-table `TrackSort` orders + their EXPLAIN plans.
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

import Foundation
import LibraryStore

func songsSortCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "ss1-sort-order-tiebreak", run: checkSongsSortOrder),
        CheckCase(label: "ss2-sort-explain-plan", run: checkSongsSortQueryPlan),
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
