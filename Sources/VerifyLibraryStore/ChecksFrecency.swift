// ChecksFrecency — the S10.6 Recently-Played frecency algorithm checks (design §6, FR1–FR8).
//
// Drives the REAL LibraryStore: the write DAO (`incrementPlayCount(id:playedAt:)`), the read
// (`frecencyTracksDisplay`), the verification hook (`frecencyState(id:)`), and the EXPLAIN hook —
// asserting against expectations DERIVED from the pure `LibraryStore.frecencyAfterPlay` (never
// magic numbers). Proves the accumulator/rank math, recency-outweighs-count ordering, the
// rank≡current-frecency order-equivalence, never-played exclusion, the backward-clock clamp, and
// the index-driven (no-filesort) read. The ≥60% "heard" rule is proven separately by the pure
// `PlayThroughTracker` under `swift test`.

import Foundation
import GRDB
import LibraryScan
import LibraryStore

private let frecencyEps = 1e-6
private let halfLife = LibraryStore.frecencyHalfLifeSeconds
private let baseTime: Int64 = 1_700_000_000

/// FR1 — first play: play_count 1, score 1.0, rank == last_played (ln 1 = 0).
func checkFrecencyFirstPlay(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/Fr", paths: ["/Fr/a.flac"])
        let id = seeded.trackIDs[0]
        try await seeded.store.incrementPlayCount(id: id, playedAt: baseTime)
        guard let state = try await seeded.store.frecencyState(id: id) else {
            printFail(number, "FR1: no frecency state after first play"); return false
        }
        guard state.playCount == 1, abs(state.score - 1.0) < frecencyEps, state.lastPlayed == baseTime,
              let rank = state.rank, abs(rank - Double(baseTime)) < 1e-3 else {
            printFail(number, "FR1: first play state wrong "
                + "(count=\(state.playCount) score=\(state.score) rank=\(String(describing: state.rank)))")
            return false
        }
        printPass(number, "FR1: first play → play_count 1, score 1.0, rank == last_played (ln 1 = 0)")
        return true
    } catch { printFail(number, "FR1 threw: \(error)"); return false }
}

/// FR2 — decay accumulation: two plays a half-life apart → score == 1·2⁻¹ + 1 == 1.5, matching the
/// pure helper (formula-derived, not magic).
func checkFrecencyDecayAccumulation(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/Fr", paths: ["/Fr/a.flac"])
        let id = seeded.trackIDs[0]
        try await seeded.store.incrementPlayCount(id: id, playedAt: baseTime)
        let second = baseTime + Int64(halfLife)
        try await seeded.store.incrementPlayCount(id: id, playedAt: second)
        let expected = LibraryStore.frecencyAfterPlay(prevScore: 1.0, lastPlayed: baseTime, now: second)
        guard let state = try await seeded.store.frecencyState(id: id), state.playCount == 2,
              abs(state.score - expected.score) < frecencyEps, abs(expected.score - 1.5) < 1e-9 else {
            printFail(number, "FR2: Δt=half-life accumulation != 1.5"); return false
        }
        printPass(number, "FR2: two plays a half-life apart → score 1.5 (decay accumulate, formula-derived)")
        return true
    } catch { printFail(number, "FR2 threw: \(error)"); return false }
}

/// FR3 — burst vs spread (the correctness property the naive `count×decay` model fails): 3 plays at
/// one instant (score 3) rank ABOVE 3 plays spaced a half-life (score 1.75).
func checkFrecencyBurstVsSpread(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/Fr", paths: ["/Fr/burst.flac", "/Fr/spread.flac"])
        let burst = seeded.trackIDs[0], spread = seeded.trackIDs[1]
        for _ in 0 ..< 3 {
            try await seeded.store.incrementPlayCount(id: burst, playedAt: baseTime)
        }
        for step in 0 ..< 3 {
            try await seeded.store.incrementPlayCount(id: spread, playedAt: baseTime + Int64(step) * Int64(halfLife))
        }
        guard let burstState = try await seeded.store.frecencyState(id: burst),
              let spreadState = try await seeded.store.frecencyState(id: spread),
              abs(burstState.score - 3.0) < frecencyEps, abs(spreadState.score - 1.75) < frecencyEps,
              burstState.score > spreadState.score else {
            printFail(number, "FR3: burst not > spread"); return false
        }
        printPass(number, "FR3: burst (3× at once, score 3) > spread (3× a half-life apart, score 1.75) "
            + "— recency-weighting proven (the naive count×decay model fails this)")
        return true
    } catch { printFail(number, "FR3 threw: \(error)"); return false }
}

/// FR4 — recency outweighs count (via the read): 3 recent plays rank ABOVE 30 plays 30 days stale
/// (H=7d). Order derived from the ranks, then confirmed by `frecencyTracksDisplay`.
func checkFrecencyRecencyOutweighsCount(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/Fr", paths: ["/Fr/recent.flac", "/Fr/stale.flac"])
        let recent = seeded.trackIDs[0], stale = seeded.trackIDs[1]
        let staleTime = baseTime - 30 * 86400
        for _ in 0 ..< 3 {
            try await seeded.store.incrementPlayCount(id: recent, playedAt: baseTime)
        }
        for _ in 0 ..< 30 {
            try await seeded.store.incrementPlayCount(id: stale, playedAt: staleTime)
        }
        guard let recentState = try await seeded.store.frecencyState(id: recent),
              let staleState = try await seeded.store.frecencyState(id: stale),
              let recentRank = recentState.rank, let staleRank = staleState.rank else {
            printFail(number, "FR4: missing state"); return false
        }
        // Derived: 3-recent must out-rank 30-stale despite the 10× count gap.
        guard recentRank > staleRank else {
            printFail(number, "FR4: recent rank (\(recentRank)) !> stale rank (\(staleRank))"); return false
        }
        let order = try await seeded.store.frecencyTracksDisplay().map(\.id)
        guard order.first == recent, order.contains(stale), order.count == 2 else {
            printFail(number, "FR4: read order \(order) did not put recent first"); return false
        }
        printPass(number, "FR4: 3 recent plays out-rank 30 plays 30 days stale (H=7d) — read confirms recency > count")
        return true
    } catch { printFail(number, "FR4 threw: \(error)"); return false }
}

/// FR5 — never-played rows are excluded (`WHERE play_count > 0`).
func checkFrecencyNeverPlayedExcluded(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/Fr", paths: ["/Fr/a.flac", "/Fr/b.flac", "/Fr/c.flac"])
        let played = seeded.trackIDs[1]
        try await seeded.store.incrementPlayCount(id: played, playedAt: baseTime)
        let ids = try await seeded.store.frecencyTracksDisplay().map(\.id)
        guard ids == [played] else {
            printFail(number, "FR5: expected only the played id, got \(ids)"); return false
        }
        printPass(number, "FR5: never-played tracks absent from the frecency read (only play_count > 0)")
        return true
    } catch { printFail(number, "FR5 threw: \(error)"); return false }
}

/// FR6 — rank order ≡ current-frecency order (the R2 core proof, empirically): several tracks with
/// varied (count, recency); the `frecencyTracksDisplay` order equals the order by independently
/// computed current frecency `score·2^(−(t−lp)/H)` at an arbitrary read time `t`.
func checkFrecencyOrderEquivalence(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(
            url, root: "/Fr", paths: ["/Fr/0.flac", "/Fr/1.flac", "/Fr/2.flac", "/Fr/3.flac"]
        )
        // Distinct histories: (plays, secondsAgo-from-baseTime).
        let plans: [(count: Int, ago: Int64)] = [(1, 0), (5, 20 * 86400), (2, 3 * 86400), (12, 40 * 86400)]
        for (index, plan) in plans.enumerated() {
            for _ in 0 ..< plan.count {
                try await seeded.store.incrementPlayCount(id: seeded.trackIDs[index], playedAt: baseTime - plan.ago)
            }
        }
        let readOrder = try await seeded.store.frecencyTracksDisplay().map(\.id)
        // Independent current-frecency at a read time comfortably after the newest play.
        let readNow = Double(baseTime + 86400)
        var scored: [(id: Int64, freq: Double)] = []
        for id in seeded.trackIDs {
            guard let state = try await seeded.store.frecencyState(id: id), let rank = state.rank else { continue }
            // current frecency = 2^((rank − t)/H) — the proven identity.
            scored.append((id, pow(2.0, (rank - readNow) / halfLife)))
        }
        let expected = scored.sorted { $0.freq > $1.freq }.map(\.id)
        guard readOrder == expected else {
            printFail(number, "FR6: read order \(readOrder) != current-frecency order \(expected)"); return false
        }
        printPass(number, "FR6: frecencyTracksDisplay order ≡ order by current frecency 2^((rank−t)/H) "
            + "(the R2 projected-rank equivalence, verified end-to-end)")
        return true
    } catch { printFail(number, "FR6 threw: \(error)"); return false }
}

/// FR7 — backward clock jump does NOT inflate the score (age clamped to ≥ 0): a second play stamped
/// EARLIER than the first accumulates as `prev·1 + 1`, matching the clamped pure helper.
func checkFrecencyBackwardClockClamp(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/Fr", paths: ["/Fr/a.flac"])
        let id = seeded.trackIDs[0]
        try await seeded.store.incrementPlayCount(id: id, playedAt: baseTime)
        let backward = baseTime - 100 // clock jumped backward
        try await seeded.store.incrementPlayCount(id: id, playedAt: backward)
        let expected = LibraryStore.frecencyAfterPlay(prevScore: 1.0, lastPlayed: baseTime, now: backward)
        guard let state = try await seeded.store.frecencyState(id: id),
              abs(state.score - expected.score) < frecencyEps, abs(expected.score - 2.0) < 1e-9 else {
            printFail(number, "FR7: backward clock jump inflated the score (expected clamped 2.0)"); return false
        }
        printPass(number, "FR7: backward clock jump clamps age≥0 → score 2.0 (no decay-factor inflation)")
        return true
    } catch { printFail(number, "FR7 threw: \(error)"); return false }
}

/// FR8 — the read is INDEX-driven: `EXPLAIN QUERY PLAN` uses `idx_tracks_frecency_rank` and has NO
/// `USE TEMP B-TREE FOR ORDER BY` (the projected-rank + rowid-carrying index removed the filesort).
func checkFrecencyReadIndexed(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/Fr", paths: ["/Fr/a.flac"])
        try await seeded.store.incrementPlayCount(id: seeded.trackIDs[0], playedAt: baseTime)
        let plan = try await seeded.store.explainFrecencyTracksDisplayPlan()
        let joined = plan.joined(separator: " | ").uppercased()
        guard joined.contains("IDX_TRACKS_FRECENCY_RANK"), !joined.contains("TEMP B-TREE") else {
            printFail(number, "FR8: frecency read not index-driven / has a temp b-tree: \(plan)"); return false
        }
        printPass(number, "FR8: frecency read uses idx_tracks_frecency_rank with NO temp b-tree (filesort gone)")
        return true
    } catch { printFail(number, "FR8 threw: \(error)"); return false }
}
