// ChecksQueryPlan — the EXPLAIN QUERY PLAN scale tripwire for the browse reads (BR5) plus the
// shared plan-parsing helpers (`detailUsesIndex` / `detailIsTracksTableScan`). Split from
// ChecksBrowseReads so the helpers — ALSO used by ChecksSongsSort and ChecksSearchFilter — live in
// a neutral home instead of inside one consumer. BR5 asserts every hot facet read is
// SEARCH … USING INDEX, never a full SCAN of `tracks` (aliases t/t2) — the portable scale invariant
// (it holds because the store runs no ANALYZE/sqlite_stat1/PRAGMA optimize, so the planner picks
// indexes from the schema, not row-count stats, even on the tiny fixture).

import Foundation
import LibraryStore

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
            + "albums(inGenre:) is SEARCH … USING INDEX — never SCAN TABLE tracks (aliases t/t2)")
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
