// ChecksSearchFilter — S9.5 §4 (A2 LOCKED): the IDs-only membership read behind the
// Songs "filter-preserves-sort" filter, `searchMatchingIDs(_:)`. Split out of
// ChecksSearch (file-length budget), same VerifyAUGraph idiom (Bool return, one
// numbered PASS line).
//
//   MID  membership parity vs an UNBOUNDED `search()` (common token / prefix /
//        diacritic / multi-token-AND / tokenizable-no-match); junk('!!!')/empty → [];
//        EXPLAIN QUERY PLAN visits `tracks_fts` ONLY, never scans the `tracks` table.

import Foundation
import LibraryScan
import LibraryStore

// MARK: - MID — searchMatchingIDs parity + junk/empty + EXPLAIN (design §4, A2 LOCKED)

func checkFtsMatchingIDsParity(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let generation = try await store.beginScanGeneration()
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/MID"))
        // A spread exercising a common token (dark×3), a prefix (dar), a multi-token AND
        // (dark side → 1), and two diacritic folds (café→cafe, ö→o). Filenames are neutral;
        // once applyMetadata sets a tag title the filename is no longer indexed (SYNC2), so
        // it can never perturb the query membership.
        let seeds: [(String, TrackMetadata)] = [
            ("s1.flac", TrackMetadata(title: "Dark Side of the Moon", artistName: "Pink Floyd")),
            ("s2.flac", TrackMetadata(title: "Dark Star", artistName: "Grateful Dead")),
            ("s3.flac", TrackMetadata(title: "Dark Matter Rising", artistName: "Muse")),
            ("s4.flac", TrackMetadata(title: "Café del Mar", artistName: "Energy 52")),
            ("s5.flac", TrackMetadata(title: "Motörhead Anthem", artistName: "Lemmy")),
            ("s6.flac", TrackMetadata(title: "Bright Lights", artistName: "Placebo")),
        ]
        for (index, seed) in seeds.enumerated() {
            let ids = try await store.upsert(
                [makeScanned(path: "/Music/MID/\(seed.0)", name: seed.0, inode: Int64(300 + index))],
                folderID: root, generation: generation
            )
            try await store.applyMetadata(seed.1, forTrack: ids[0])
        }
        guard try await checkMatchingIDsParity(store, number: number),
              try await checkMatchingIDsJunkEmpty(store, number: number),
              try await checkMatchingIDsExplain(store, number: number) else { return false }
        printPass(number, "MID: searchMatchingIDs membership == Set(search(unbounded).tracks.id) for "
            + "common-token/prefix/diacritic/multi-token-AND/no-match queries; junk('!!!')/empty → []; "
            + "EXPLAIN visits tracks_fts only, never scans tracks")
        return true
    } catch {
        printFail(number, "MID threw: \(error)"); return false
    }
}

/// `searchMatchingIDs(q)` must equal the ids of an UNBOUNDED `search(q)` for every query
/// class. The comparison uses `limit: .max` (NOT the default 400) because `searchMatchingIDs`
/// is uncapped — a >400-match fixture would legitimately make it a SUPERSET of a 400-capped
/// search. This fixture matches ≤3 rows per query (far below any cap), so the two are exactly
/// equal here; the `.max` limit removes the cap as a confound. The ≥1-match cases also pin the
/// parity as non-vacuous (not both-empty-and-equal); the 0-match case pins that a tokenizable
/// query that hits nothing returns `[]` (never all rows).
private func checkMatchingIDsParity(_ store: LibraryStore, number: Int) async throws -> Bool {
    let cases: [(query: String, expected: Int)] = [
        ("dark", 3), // common token / implicit prefix over 3 titles
        ("dar", 3), // explicit prefix
        ("cafe", 1), // diacritic fold café→cafe
        ("motorhead", 1), // diacritic fold ö→o
        ("dark side", 1), // multi-token implicit-AND
        ("zqxjwv", 0), // tokenizable, matches nothing → [] via the SQL path (not the nil path)
    ]
    for testCase in cases {
        let ids = try await store.searchMatchingIDs(testCase.query)
        let searched = try Set(await store.search(testCase.query, limit: Int.max).tracks.map(\.id))
        guard ids == searched else {
            printFail(number, "MID: '\(testCase.query)' membership \(ids.sorted()) != "
                + "unbounded search set \(searched.sorted())"); return false
        }
        guard ids.count == testCase.expected else {
            printFail(number, "MID: '\(testCase.query)' matched \(ids.count), expected "
                + "\(testCase.expected)"); return false
        }
    }
    return true
}

/// Junk / all-stripped input (`ftsMatchQuery → nil`) returns an EMPTY set — never all rows,
/// never a throw. Mirrors `search()`'s `.empty` for the same input (ChecksSearch Q2).
private func checkMatchingIDsJunkEmpty(_ store: LibraryStore, number: Int) async throws -> Bool {
    for junk in ["!!!", "", "   ", "* : ( )", "½ ①"] {
        guard try await store.searchMatchingIDs(junk).isEmpty else {
            printFail(number, "MID: junk/empty '\(junk)' did not return an empty set"); return false
        }
    }
    return true
}

/// The `searchMatchingIDs` plan must NOT scan the `tracks` table. A `SCAN tracks_fts`
/// virtual-table step is expected and fine — `detailIsTracksTableScan` (the SAME BR5
/// tripwire) does not flag it (target `TRACKS_FTS` ∉ {T,T2,TRACKS}); the tripwire fires
/// only on a real `tracks` scan, which this joinless membership read must never do.
private func checkMatchingIDsExplain(_ store: LibraryStore, number: Int) async throws -> Bool {
    let details = try await store.explainSearchMatchingIDsPlan()
    guard !details.isEmpty else {
        printFail(number, "MID: empty EXPLAIN QUERY PLAN for searchMatchingIDs"); return false
    }
    guard !details.contains(where: detailIsTracksTableScan) else {
        printFail(number, "MID: searchMatchingIDs plan SCANs the tracks table: \(details)"); return false
    }
    return true
}
