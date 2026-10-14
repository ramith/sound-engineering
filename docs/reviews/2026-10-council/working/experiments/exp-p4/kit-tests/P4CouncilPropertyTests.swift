import Foundation
import PlaybackQueueKit
import Testing

// Council P4 (queue / transport) — property and exhaustive tests against the REAL PlaybackQueueKit.
// Scratch, uncommitted (panel-p4 worktree). Oracles are written from the spec, not from the code.

@Suite("P4 council — PlaybackQueueKit properties")
struct P4CouncilPropertyTests {
    // MARK: N3 — the shuffle pick: uniform over the other slots (chi-square), never current

    /// Chi-square critical values at p = 0.001 for df 1...10 (NIST/SEMATECH e-Handbook, Table 1.3.6.7.4).
    private static let chi2Crit001: [Double] = [10.828, 13.816, 16.266, 18.467, 20.515, 22.458, 24.322, 26.124,
                                                27.877, 29.588]

    @Test("P4-N3-uniform: uniformRandomExcluding is uniform over the count-1 other slots (chi-square, p=0.001)")
    func shufflePickUniform() {
        var worst = 0.0
        var rejections = 0
        var cells = 0
        for count in 2 ... 11 {
            for current in 0 ..< count {
                let draws = 20000
                var hist = [Int](repeating: 0, count: count)
                for _ in 0 ..< draws {
                    hist[QueueAdvance.uniformRandomExcluding(current, count)] += 1
                }
                #expect(hist[current] == 0)
                let expected = Double(draws) / Double(count - 1)
                var chi2 = 0.0
                for slot in 0 ..< count where slot != current {
                    chi2 += pow(Double(hist[slot]) - expected, 2) / expected
                }
                let df = count - 2
                cells += 1
                if df >= 1 {
                    worst = max(worst, chi2 / Self.chi2Crit001[df - 1])
                    if chi2 > Self.chi2Crit001[df - 1] { rejections += 1 }
                }
            }
        }
        print("P4-N3-uniform: \(cells) (count,current) cells, worst chi2/crit = \(worst), rejections = \(rejections)")
        // 65 cells with df >= 1 at p = 0.001: P(any false rejection) ≈ 6 %; allow one.
        #expect(rejections <= 1)
    }

    // MARK: N1/N2 — next / previous against a spec oracle, exhaustively over small queues

    /// The spec (written from the doc comments + the established players' rules, not the code):
    /// repeat-one auto-advance repeats; shuffle with > 1 track picks among the others; otherwise
    /// linear, wrapping only under repeat-all.
    private static func specNext(_ current: Int, _ count: Int, _ shuffle: Bool, _ repeatMode: Int, _ manual: Bool,
                                 _ pick: (Int, Int) -> Int) -> Int? {
        if count == 0 { return nil }
        if repeatMode == 2, !manual { return current }
        if shuffle, count > 1 { return pick(current, count) }
        if current + 1 < count { return current + 1 }
        return repeatMode == 1 ? 0 : nil
    }

    @Test("P4-N1-exhaustive: nextIndex == spec for count 0...7, every current incl. out-of-range, every mode")
    func nextExhaustive() {
        let pick: (Int, Int) -> Int = { current, count in (current + 3) % count == current ? (current + 1) % count
            : (current + 3) % count }
        var cases = 0
        var outOfRange: [String] = []
        for count in 0 ... 7 {
            for current in -1 ... count + 1 {
                for shuffle in [false, true] {
                    for repeatMode in 0 ... 2 {
                        for manual in [false, true] {
                            cases += 1
                            let got = QueueAdvance.nextIndex(current: current, count: count, shuffle: shuffle,
                                                             repeatMode: repeatMode, manualSkip: manual, randomPick: pick)
                            #expect(got == Self.specNext(current, count, shuffle, repeatMode, manual, pick))
                            if let got, got < 0 || got >= count {
                                outOfRange.append("next(c=\(current),n=\(count),s=\(shuffle),r=\(repeatMode),m=\(manual))=\(got)")
                            }
                            let prev = QueueAdvance.previousIndex(current: current, count: count, shuffle: shuffle,
                                                                  repeatMode: repeatMode, randomPick: pick)
                            if let prev, prev < 0 || prev >= count {
                                outOfRange.append("prev(c=\(current),n=\(count),s=\(shuffle),r=\(repeatMode))=\(prev)")
                            }
                        }
                    }
                }
            }
        }
        print("P4-N1-exhaustive: \(cases) cases; out-of-range results for out-of-range `current`: \(outOfRange.count) "
            + "e.g. \(outOfRange.prefix(4))")
    }

    @Test("P4-N1-shuffle-pass: a shuffled pass with repeat OFF — does it ever end, does it cover every track once?")
    func shufflePassNeverEnds() {
        // Drive nextIndex with the production picker the way the auto-advance does (manualSkip false).
        var endedRuns = 0
        var coverage: [Int] = []
        var repeatsBeforeCover: [Int] = []
        for _ in 0 ..< 2000 {
            let count = 10
            var current = 0
            var seen: Set<Int> = [0]
            var plays = 1
            var repeats = 0
            while plays < 1000 {
                guard let next = QueueAdvance.nextIndex(current: current, count: count, shuffle: true, repeatMode: 0,
                                                        randomPick: QueueAdvance.uniformRandomExcluding)
                else { endedRuns += 1; break }
                if seen.contains(next), seen.count < count { repeats += 1 }
                seen.insert(next)
                current = next
                plays += 1
                if seen.count == count, coverage.count < 2000 {
                    coverage.append(plays)
                    repeatsBeforeCover.append(repeats)
                    break
                }
            }
        }
        let meanPlays = Double(coverage.reduce(0, +)) / Double(max(coverage.count, 1))
        let meanRepeats = Double(repeatsBeforeCover.reduce(0, +)) / Double(max(repeatsBeforeCover.count, 1))
        print("P4-N1-shuffle-pass: 10 tracks, repeat off: runs that END = \(endedRuns)/2000; mean plays to hear all 10 "
            + "= \(meanPlays) (a permutation needs exactly 10); mean repeats before full coverage = \(meanRepeats)")
        #expect(endedRuns == 0) // documents today's behaviour: a shuffled queue never ends
    }

    // MARK: N6 — QueueInsert.playNextNow: model-based, with DUPLICATE tracks (allowed since S10.2)

    @Test("P4-N6-model: playNextNow — the clicked track plays right after the current, the rest keeps its order")
    func playNextNowModel() {
        var rng = SystemRandomNumberGenerator()
        var violations: [String] = []
        var cases = 0
        for _ in 0 ..< 20000 {
            let count = Int.random(in: 0 ... 6, using: &rng)
            // Track values 0...3 so duplicates are common; each slot has a unique identity (its offset).
            let tracks = (0 ..< count).map { _ in Int.random(in: 0 ... 3, using: &rng) }
            let current: Int? = count == 0 || Bool.random(using: &rng) ? nil : Int.random(in: 0 ..< count, using: &rng)
            let clicked = Int.random(in: 0 ... 4, using: &rng)
            let existing = tracks.firstIndex(of: clicked)
            cases += 1
            let move = QueueInsert.playNextNow(current: current, existing: existing, count: count)
            // Apply the move as the VM does (+Queue.swift:150-163).
            var slots = Array(tracks.indices) // slot identities
            var values = tracks
            let playing: Int
            switch move {
            case let .restartCurrent(index):
                playing = index
            case let .insertAndPlay(removeAt, insertAt):
                if let removeAt { slots.remove(at: removeAt); values.remove(at: removeAt) }
                slots.insert(-1, at: insertAt)
                values.insert(clicked, at: insertAt)
                playing = insertAt
            }
            // SPEC (Music.app / the doc comment): the clicked track plays now ...
            if values[playing] != clicked { violations.append("plays \(values[playing]) not clicked \(clicked)") }
            if let current {
                let currentSlot = current // identity of the slot that was playing
                if tracks[current] == clicked {
                    // ... re-clicking the PLAYING track restarts THAT slot in place (no move).
                    if slots[playing] != currentSlot || values.count != tracks.count {
                        violations.append("re-click of playing track \(clicked) at \(current) in \(tracks): "
                            + "moved/added instead of restart → \(values), plays slot \(slots[playing])")
                    }
                } else if playing == 0 || slots[playing - 1] != currentSlot {
                    // ... immediately after the slot that was playing.
                    violations.append("clicked \(clicked) not right after the playing slot in \(tracks)@\(current) → \(values)")
                }
            }
        }
        print("P4-N6-model: \(cases) cases, \(violations.count) violations; first: \(violations.prefix(3))")
        #expect(violations.isEmpty)
    }

    // MARK: N7 — QueueRestorePoint: arbitrary replace / edit / restore sequences vs an oracle

    private struct Slot: Identifiable, Equatable {
        let id: Int
    }

    @Test("P4-N7-model: Restore brings back the user's own queue (identities intact) after any replace/edit sequence")
    func restorePointModel() {
        var rng = SystemRandomNumberGenerator()
        var nextID = 1000
        var violations: [String] = []
        for _ in 0 ..< 20000 {
            var queue = (0 ..< Int.random(in: 0 ... 4, using: &rng)).map { Slot(id: $0) }
            var held: QueueRestorePoint<Slot>?
            // Oracle: the user's queue = the queue before the first replace of a run of replaces with no
            // edit in between (a double-click / Play then Shuffle replaces a replace).
            var oracle: [Slot]?
            var lastInstall: [Int]? // ids the last replace installed
            for _ in 0 ..< Int.random(in: 1 ... 8, using: &rng) {
                switch Int.random(in: 0 ... 3, using: &rng) {
                case 0, 1: // an undoable replace installs fresh slots
                    let installed = (0 ..< Int.random(in: 1 ... 3, using: &rng)).map { _ -> Slot in
                        nextID += 1
                        return Slot(id: nextID)
                    }
                    // "untouched" per the doc: the same slots in the same order as the last install
                    if lastInstall != queue.map(\.id) { oracle = queue }
                    held = .afterReplace(held: held, replaced: queue, index: nil, shuffle: false,
                                         installed: installed.map(\.id))
                    queue = installed
                    lastInstall = installed.map(\.id)
                case 2: // a user edit (append a fresh slot, or remove one)
                    if !queue.isEmpty, Bool.random(using: &rng) {
                        queue.remove(at: Int.random(in: 0 ..< queue.count, using: &rng))
                    } else {
                        nextID += 1
                        queue.append(Slot(id: nextID))
                    }
                default: // a reorder that is NOT a no-op
                    if queue.count >= 2 {
                        queue.swapAt(0, queue.count - 1)
                    }
                }
            }
            if let held, let oracle, held.slots != oracle {
                violations.append("restores \(held.slots.map(\.id)) expected \(oracle.map(\.id))")
            }
        }
        print("P4-N7-model: \(violations.count) violations; first: \(violations.prefix(3))")
        #expect(violations.isEmpty)
    }

    // MARK: N8 — ResumePoint is keyed by slot identity

    @Test("P4-N8: a resume point answers only for its own slot, whatever row it moves to")
    func resumePointIdentity() {
        let slots = (0 ..< 6).map { _ in UUID() }
        for owner in slots {
            var point = ResumePoint(slot: owner, seconds: 42)
            for other in slots {
                #expect(point.seconds(resuming: other) == (other == owner ? 42 : nil))
            }
            #expect(point.seconds(resuming: nil) == nil)
            point.move(to: 7)
            #expect(point.seconds(resuming: owner) == 7)
        }
    }

    // MARK: N25 — PlayThroughTracker against the Last.fm scrobble rule

    @Test("P4-N25-oracle: fires exactly once, at the first accrual reaching min(0.6·d, 240) for d ≥ 30")
    func playThroughOracle() {
        var rng = SystemRandomNumberGenerator()
        var violations: [String] = []
        for _ in 0 ..< 20000 {
            let duration = Double.random(in: 0 ... 900, using: &rng).rounded()
            var tracker = PlayThroughTracker()
            var heard = 0.0
            var fired = 0
            var firedAt: Double?
            for _ in 0 ..< 400 {
                let delta = Double.random(in: -1 ... 12, using: &rng)
                let before = heard
                if delta > 0 { heard += min(delta, 10) }
                if tracker.accrue(delta, duration: duration) {
                    fired += 1
                    firedAt = heard
                    let threshold = min(0.6 * duration, 240)
                    if !(duration >= 30 && before < threshold && heard >= threshold) {
                        violations.append("fired d=\(duration) before=\(before) after=\(heard)")
                    }
                }
            }
            let threshold = duration >= 30 ? min(0.6 * duration, 240) : Double.infinity
            if fired > 1 || (fired == 0 && heard >= threshold) {
                violations.append("d=\(duration) heard=\(heard) fired=\(fired) at \(String(describing: firedAt))")
            }
        }
        print("P4-N25-oracle: \(violations.count) violations; first: \(violations.prefix(3))")
        #expect(violations.isEmpty)
    }

    // MARK: N10 — the epoch rule over all (request, sample) pairs

    @Test("P4-N10: isCurrent is exactly 'sample epoch ≥ latest request' (incl. the UInt64 wrap the VM's &+= allows)")
    func epochRule() {
        for requested: UInt64 in [0, 1, 2, 7, UInt64.max - 1, UInt64.max] {
            for sample: UInt64 in [0, 1, 2, 7, UInt64.max - 1, UInt64.max] {
                #expect(TransportSnapshot(epoch: sample).isCurrent(for: requested) == (sample >= requested))
            }
        }
        // After a wrap (UInt64.max &+ 1 == 0) every old sample would read as current: unreachable in
        // practice (2^64 requests), noted only because `nextTransportEpoch` uses &+=.
        #expect(TransportSnapshot(epoch: UInt64.max).isCurrent(for: UInt64.max &+ 1))
    }
}
