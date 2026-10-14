import PlaybackQueueKit
import Testing

// MARK: - QueueInsert decision core (S9 — Songs-list "Play Next + jump") — the REAL logic (VM-QI)

//
// Imports the shipped `PlaybackQueueKit` target (NOT a hand-mirror), so a regression in the
// single-track jump-play index math is caught against the code that actually ships. Covers the
// cases `playTrackNextNow` must handle: already after / before / IS current, not present,
// nothing-playing, empty-queue — and, since the queue may hold a track more than once (S10.2),
// duplicates: which SLOT holds the clicked track decides (council C-17, N6). An already-queued
// track's first slot is MOVED (removed then re-inserted), never duplicated; the playing slot restarts.

@Suite("PlaybackQueueKit — QueueInsert.playNextNow decision core (VM-QI)")
struct QueueInsertTests {
    /// The move for clicking `track` in `queue` (track values per slot) while slot `playing` plays.
    private func move(_ queue: [Int], playing: Int?, click track: Int) -> PlayNextNowMove {
        QueueInsert.playNextNow(current: playing, count: queue.count) { queue[$0] == track }
    }

    @Test("VM-QI-01: track already AFTER current → remove it, insert right after current")
    func alreadyAfterCurrent() {
        // [0,1,2,3] playing 1, click 3. Removing 3 doesn't shift current (1); insert at 2.
        #expect(move([0, 1, 2, 3], playing: 1, click: 3) == .insertAndPlay(removeAt: 3, insertAt: 2))
    }

    @Test("VM-QI-02: track already BEFORE current → removal slides current down one, insert after it")
    func alreadyBeforeCurrent() {
        // [0,1,2,3] playing 2, click 0. Remove 0 → current slides 2→1, insert at 2.
        #expect(move([0, 1, 2, 3], playing: 2, click: 0) == .insertAndPlay(removeAt: 0, insertAt: 2))
        // Adjacent-before: playing 2, click 1. Remove 1 → current 2→1, insert at 2.
        #expect(move([0, 1, 2, 3], playing: 2, click: 1) == .insertAndPlay(removeAt: 1, insertAt: 2))
        // Before-current landing at the append boundary: playing 3, click 2. Remove 2 →
        // current 3→2, insert at 3 (the post-removal tail). Locks the clamp on this branch.
        #expect(move([0, 1, 2, 3], playing: 3, click: 2) == .insertAndPlay(removeAt: 2, insertAt: 3))
    }

    @Test("VM-QI-03: re-clicking the current track → restart in place (no dup, no churn)")
    func alreadyIsCurrent() {
        #expect(move([0, 1, 2, 3], playing: 1, click: 1) == .restartCurrent(index: 1))
    }

    @Test("VM-QI-04: track NOT queued, something playing → insert right after current")
    func notPresentWhilePlaying() {
        #expect(move([0, 1, 2, 3], playing: 1, click: 9) == .insertAndPlay(removeAt: nil, insertAt: 2))
        // On the last track → insert at the end (append slot).
        #expect(move([0, 1, 2, 3], playing: 3, click: 9) == .insertAndPlay(removeAt: nil, insertAt: 4))
    }

    @Test("VM-QI-05: nothing playing → front-insert (0) so the existing queue follows")
    func nothingPlaying() {
        // Not queued → front-insert, nothing removed.
        #expect(move([0, 1, 2, 3], playing: nil, click: 9) == .insertAndPlay(removeAt: nil, insertAt: 0))
        // Already queued → remove that occurrence first, still front-insert (0).
        #expect(move([0, 1, 2, 3], playing: nil, click: 2) == .insertAndPlay(removeAt: 2, insertAt: 0))
    }

    @Test("VM-QI-06: empty queue → becomes [track] at index 0")
    func emptyQueue() {
        #expect(move([], playing: nil, click: 9) == .insertAndPlay(removeAt: nil, insertAt: 0))
    }

    @Test("VM-QI-07 (N6): the playing slot holds the clicked track → restart it, never an earlier copy")
    func playingSlotWinsOverAnEarlierCopy() {
        // [A, B, A] playing the second A: restart slot 2 (it used to move slot 0 after it and play that).
        #expect(move([0, 1, 0], playing: 2, click: 0) == .restartCurrent(index: 2))
        // Playing B, click A (two copies): the first copy moves to after B.
        #expect(move([0, 1, 0], playing: 1, click: 0) == .insertAndPlay(removeAt: 0, insertAt: 1))
    }

    @Test("VM-QI-08 (council P4 N6 model): with duplicates, the clicked track plays right after the playing slot")
    func playNextNowModelWithDuplicates() {
        // Council P4's model test (E2), on the shipped rule: 20 000 random queues of tracks 0…3 (so
        // duplicates are common), each slot a unique identity. Spec (Music.app, the doc comment): the
        // clicked track plays now — re-clicking the PLAYING slot's track restarts that slot in place;
        // otherwise it plays right after the slot that was playing. A violation names its whole case.
        var violations: [String] = []
        for _ in 0 ..< 20000 {
            let count = Int.random(in: 0 ... 6)
            let tracks = (0 ..< count).map { _ in Int.random(in: 0 ... 3) }
            let current: Int? = count == 0 || Bool.random() ? nil : Int.random(in: 0 ..< count)
            let clicked = Int.random(in: 0 ... 4)
            let after = Applied(move(tracks, playing: current, click: clicked), to: tracks, clicked: clicked)
            if after.values[after.playing] != clicked {
                violations.append("plays \(after.values[after.playing]), not the clicked \(clicked)")
            }
            guard let current else { continue }
            if tracks[current] == clicked {
                if after.slots[after.playing] != current || after.values.count != tracks.count {
                    violations.append("re-click of \(clicked) playing at \(current) in \(tracks) → \(after.values)")
                }
            } else if after.playing == 0 || after.slots[after.playing - 1] != current {
                violations.append("\(clicked) not right after the playing slot: \(tracks)@\(current) → \(after.values)")
            }
        }
        #expect(violations.isEmpty, "\(violations.count) violations; first: \(violations.prefix(3))")
    }

    /// A move applied as `AudioViewModel.playTrackNextNow` applies it: the queue's slot identities (the
    /// inserted slot is -1) and track values after it, and the row that plays.
    private struct Applied {
        var slots: [Int]
        var values: [Int]
        let playing: Int

        init(_ move: PlayNextNowMove, to tracks: [Int], clicked: Int) {
            slots = Array(tracks.indices)
            values = tracks
            switch move {
            case let .restartCurrent(index):
                playing = index
            case let .insertAndPlay(removeAt, insertAt):
                if let removeAt {
                    slots.remove(at: removeAt)
                    values.remove(at: removeAt)
                }
                slots.insert(-1, at: insertAt)
                values.insert(clicked, at: insertAt)
                playing = insertAt
            }
        }
    }
}
