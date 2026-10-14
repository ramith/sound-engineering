import Foundation
import LibraryStore
import Testing

// Council P4 — frecency (N27) against an independent brute-force oracle: the score at time T is the
// sum over plays of 2^(−(T − t_i)/H) (exponential decay, half-life H; Mozilla "NewFrecency" /
// Places exponential-decay model). Scratch, uncommitted (panel-p4 worktree).

@Suite("P4 council — frecency oracle")
struct P4CouncilFrecencyTests {
    private static let halfLife = LibraryStore.frecencyHalfLifeSeconds

    private static func brute(_ plays: [Int64], at time: Int64) -> Double {
        plays.reduce(0) { $0 + pow(2.0, -Double(time - $1) / halfLife) }
    }

    /// Fold the production update over a play history (what `incrementPlayCount` stores).
    private static func fold(_ plays: [Int64]) -> (score: Double, rank: Double, last: Int64?) {
        var score = 0.0
        var rank = 0.0
        var last: Int64?
        for time in plays {
            let next = LibraryStore.frecencyAfterPlay(prevScore: score, lastPlayed: last, now: time)
            score = next.score
            rank = next.rank
            last = time
        }
        return (score, rank, last)
    }

    @Test("P4-N27-accumulator: the stored score equals the brute decayed sum at the last play (forward clock)")
    func accumulatorMatchesBrute() {
        var rng = SystemRandomNumberGenerator()
        var worst = 0.0
        for _ in 0 ..< 5000 {
            var time: Int64 = 1_700_000_000
            var plays: [Int64] = []
            for _ in 0 ..< Int.random(in: 1 ... 60, using: &rng) {
                time += Int64.random(in: 0 ... 30 * 86400, using: &rng)
                plays.append(time)
            }
            let folded = Self.fold(plays)
            let expected = Self.brute(plays, at: plays.last!)
            worst = max(worst, abs(folded.score - expected) / expected)
        }
        print("P4-N27-accumulator: worst relative error \(worst)")
        #expect(worst < 1e-12)
    }

    @Test("P4-N27-order: ORDER BY rank DESC == ORDER BY current brute frecency, at any read time after the plays")
    func rankOrderEquivalence() {
        var rng = SystemRandomNumberGenerator()
        var inversions = 0
        var comparisons = 0
        for _ in 0 ..< 400 {
            let tracks = (0 ..< 12).map { _ -> [Int64] in
                var time: Int64 = 1_700_000_000 + Int64.random(in: 0 ... 90 * 86400, using: &rng)
                return (0 ..< Int.random(in: 1 ... 25, using: &rng)).map { _ in
                    time += Int64.random(in: 60 ... 20 * 86400, using: &rng)
                    return time
                }
            }
            let latest = tracks.map { $0.last! }.max()!
            let ranks = tracks.map { Self.fold($0).rank }
            for readOffset: Int64 in [0, 3600, 7 * 86400, 365 * 86400, 10 * 365 * 86400] {
                let readTime = latest + readOffset
                let current = tracks.map { Self.brute($0, at: readTime) }
                for first in 0 ..< tracks.count {
                    for second in first + 1 ..< tracks.count {
                        let byScore = current[first] - current[second]
                        // Skip near-ties (and the underflow region where both brute sums are ~0).
                        guard abs(byScore) > 1e-9 * max(current[first], current[second]),
                              min(current[first], current[second]) > 1e-300 else { continue }
                        comparisons += 1
                        if (byScore > 0) != (ranks[first] > ranks[second]) { inversions += 1 }
                    }
                }
            }
        }
        print("P4-N27-order: \(comparisons) pair comparisons, \(inversions) inversions")
        #expect(inversions == 0)
    }

    @Test("P4-N27-long-horizon: one play a minute for two years stays finite and bounded by 1/(1−2^(−Δ/H))")
    func longHorizon() {
        var score = 0.0
        var last: Int64?
        var time: Int64 = 1_700_000_000
        var rank = 0.0
        for _ in 0 ..< 1_051_200 { // 2 years of minutes
            let next = LibraryStore.frecencyAfterPlay(prevScore: score, lastPlayed: last, now: time)
            score = next.score
            rank = next.rank
            last = time
            time += 60
        }
        let bound = 1 / (1 - pow(2.0, -60 / Self.halfLife))
        print("P4-N27-long-horizon: score \(score) (bound \(bound)), rank − now = \(rank - Double(last!)) s")
        #expect(score.isFinite && score <= bound + 1e-6 && rank.isFinite)
    }

    @Test("P4-N27-clock: the clock set back, then forward again; the clock set years ahead")
    func clockChanges() {
        let day: Int64 = 86400
        let base: Int64 = 1_700_000_000
        // A plays every day for 10 days, true time. Its true score at day 10:
        let truePlays = (0 ... 10).map { base + Int64($0) * day }
        let trueScore = Self.brute(truePlays, at: truePlays.last!)
        // Same plays, but day 5's play happens while the clock reads 7 days behind.
        var skewed = truePlays
        skewed[5] -= 7 * day
        let skewedFold = Self.fold(skewed)
        print("P4-N27-clock: back-7d at play 5 → final score \(skewedFold.score) vs true \(trueScore) "
            + "(ratio \(skewedFold.score / trueScore))")
        // One play stamped 5 years ahead (clock wrong), then the clock is fixed.
        let ahead = Self.fold([base, base + 5 * 365 * day])
        let normal = Self.fold([base + day, base + 2 * day, base + 3 * day])
        print("P4-N27-clock: one play stamped +5 y → rank \(ahead.rank) vs a track played 3× this week → "
            + "rank \(normal.rank): the mis-stamped track stays above it for ~\((ahead.rank - normal.rank) / Double(day)) days")
        #expect(skewedFold.score.isFinite)
    }
}
