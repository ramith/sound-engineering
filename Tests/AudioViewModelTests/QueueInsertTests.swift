import PlaybackQueueKit
import Testing

// MARK: - QueueInsert decision core (S9 — Songs-list "Play Next + jump") — the REAL logic (VM-QI)

//
// Imports the shipped `PlaybackQueueKit` target (NOT a hand-mirror), so a regression in the
// single-track jump-play index math is caught against the code that actually ships. Covers the
// six cases `playTrackNextNow` must handle: already after / before / IS current, not present,
// nothing-playing, empty-queue. The queue forbids duplicate URLs, so an already-queued track is
// MOVED (removed then re-inserted), never duplicated.

@Suite("PlaybackQueueKit — QueueInsert.playNextNow decision core (VM-QI)")
struct QueueInsertTests {
    @Test("VM-QI-01: track already AFTER current → remove it, insert right after current")
    func alreadyAfterCurrent() {
        // [0,1,2,3] playing 1, click 3. Removing 3 doesn't shift current (1); insert at 2.
        #expect(QueueInsert.playNextNow(current: 1, existing: 3, count: 4)
            == .insertAndPlay(removeAt: 3, insertAt: 2))
    }

    @Test("VM-QI-02: track already BEFORE current → removal slides current down one, insert after it")
    func alreadyBeforeCurrent() {
        // [0,1,2,3] playing 2, click 0. Remove 0 → current slides 2→1, insert at 2.
        #expect(QueueInsert.playNextNow(current: 2, existing: 0, count: 4)
            == .insertAndPlay(removeAt: 0, insertAt: 2))
        // Adjacent-before: playing 2, click 1. Remove 1 → current 2→1, insert at 2.
        #expect(QueueInsert.playNextNow(current: 2, existing: 1, count: 4)
            == .insertAndPlay(removeAt: 1, insertAt: 2))
        // Before-current landing at the append boundary: playing 3, click 2. Remove 2 →
        // current 3→2, insert at 3 (the post-removal tail). Locks the clamp on this branch.
        #expect(QueueInsert.playNextNow(current: 3, existing: 2, count: 4)
            == .insertAndPlay(removeAt: 2, insertAt: 3))
    }

    @Test("VM-QI-03: re-clicking the current track → restart in place (no dup, no churn)")
    func alreadyIsCurrent() {
        #expect(QueueInsert.playNextNow(current: 1, existing: 1, count: 4) == .restartCurrent(index: 1))
    }

    @Test("VM-QI-04: track NOT queued, something playing → insert right after current")
    func notPresentWhilePlaying() {
        #expect(QueueInsert.playNextNow(current: 1, existing: nil, count: 4)
            == .insertAndPlay(removeAt: nil, insertAt: 2))
        // On the last track → insert at the end (append slot).
        #expect(QueueInsert.playNextNow(current: 3, existing: nil, count: 4)
            == .insertAndPlay(removeAt: nil, insertAt: 4))
    }

    @Test("VM-QI-05: nothing playing → front-insert (0) so the existing queue follows")
    func nothingPlaying() {
        // Not queued → front-insert, nothing removed.
        #expect(QueueInsert.playNextNow(current: nil, existing: nil, count: 4)
            == .insertAndPlay(removeAt: nil, insertAt: 0))
        // Already queued → remove that occurrence first, still front-insert (0).
        #expect(QueueInsert.playNextNow(current: nil, existing: 2, count: 4)
            == .insertAndPlay(removeAt: 2, insertAt: 0))
    }

    @Test("VM-QI-06: empty queue → becomes [track] at index 0")
    func emptyQueue() {
        #expect(QueueInsert.playNextNow(current: nil, existing: nil, count: 0)
            == .insertAndPlay(removeAt: nil, insertAt: 0))
    }
}
