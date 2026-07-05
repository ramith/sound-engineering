import Testing

// MARK: - Queue ops (S9-Q2): Play Now / Play Next / Add to Queue (VM-Q)

//
// Drives the MockAdvanceController state machine (AudioViewModel+Queue can't be
// @testable-imported from the executable target). The one real decision — the append
// re-arm — is the shipped `QueueAdvance.appendArmIndex` (also gated directly in
// QueueAdvanceTests VM-QA-09); the rest is array + on-deck sequencing.

@Suite("AudioViewModel — queue ops (VM-Q)")
struct QueueOpsTests {
    @Test("VM-Q-01: playNow replaces the queue, plays from startAt, primes the on-deck")
    func playNowReplacesAndPlays() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 1) // pre-existing queue is discarded
        ctrl.playNow(makeTracks(count: 3), startAt: 1)
        #expect(ctrl.playlist.count == 3)
        #expect(ctrl.selectedTrackIndex == 1)
        #expect(ctrl.isPlaying == true)
        #expect(ctrl.pendingNextIndex == 2, "on-deck primed to the linear next after startAt")
    }

    @Test("VM-Q-02: append mid-list leaves the primed on-deck untouched")
    func appendMidListLeavesOnDeck() {
        let ctrl = MockAdvanceController()
        ctrl.playNow(makeTracks(count: 3), startAt: 0) // playing 0, on-deck 1
        #expect(ctrl.pendingNextIndex == 1)
        ctrl.appendToQueue(["new.flac"])
        #expect(ctrl.playlist.count == 4)
        #expect(ctrl.pendingNextIndex == 1, "a mid-list append must not disturb the on-deck")
    }

    @Test("VM-Q-03: append at the linear end-of-queue arms the first appended track")
    func appendAtEndArms() {
        let ctrl = MockAdvanceController()
        ctrl.playNow(makeTracks(count: 2), startAt: 0)
        ctrl.engineTransitionCount = 1
        ctrl.tick() // advance to the last track; no-repeat → on-deck nil
        #expect(ctrl.selectedTrackIndex == 1)
        #expect(ctrl.pendingNextIndex == nil)
        ctrl.appendToQueue(["c.flac"])
        #expect(ctrl.pendingNextIndex == 2, "the appended track becomes the immediate next")
        #expect(ctrl.lastNextTrackURL == "c.flac")
    }

    @Test("VM-Q-04: append under shuffle never re-rolls the primed on-deck")
    func appendUnderShuffleNoReRoll() {
        let ctrl = MockAdvanceController()
        ctrl.shuffleEnabled = true
        ctrl.playNow(makeTracks(count: 3), startAt: 0)
        let deckBefore = ctrl.pendingNextIndex
        ctrl.appendToQueue(["d.flac"])
        #expect(ctrl.playlist.count == 4)
        #expect(ctrl.pendingNextIndex == deckBefore, "shuffle append must not re-roll the pick")
    }

    @Test("VM-Q-05: append while stopped just enqueues (no arm, no playback)")
    func appendWhileStopped() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 2)
        ctrl.appendToQueue(["x.flac"])
        #expect(ctrl.playlist.count == 3)
        #expect(ctrl.isPlaying == false)
        #expect(ctrl.pendingNextIndex == nil)
    }

    @Test("VM-Q-06: playNext inserts after current and arms it as the immediate next")
    func playNextInsertsAndArms() {
        let ctrl = MockAdvanceController()
        ctrl.playNow(makeTracks(count: 3), startAt: 0)
        ctrl.playNext(["jump.flac"])
        #expect(ctrl.playlist.count == 4)
        #expect(ctrl.playlist[1] == "jump.flac")
        #expect(ctrl.pendingNextIndex == 1)
        #expect(ctrl.lastNextTrackURL == "jump.flac")
    }

    @Test("VM-Q-07: playNext under shuffle still forces the inserted track next (single-slot override)")
    func playNextOverridesShuffle() {
        let ctrl = MockAdvanceController()
        ctrl.shuffleEnabled = true
        ctrl.playNow(makeTracks(count: 5), startAt: 2)
        ctrl.playNext(["next.flac"])
        #expect(ctrl.playlist[3] == "next.flac")
        #expect(ctrl.pendingNextIndex == 3, "Play Next is honored even under shuffle")
        #expect(ctrl.lastNextTrackURL == "next.flac")
    }

    @Test("VM-Q-08: playNext with nothing selected falls back to append")
    func playNextWhileStoppedAppends() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 2) // no selectedTrackIndex
        ctrl.playNext(["y.flac"])
        #expect(ctrl.playlist.count == 3)
        #expect(ctrl.playlist.last == "y.flac")
        #expect(ctrl.pendingNextIndex == nil)
    }

    @Test("VM-Q-09: playNext while PAUSED inserts after current (not appended to the end)")
    func playNextPausedInsertsAfterCurrent() {
        let ctrl = MockAdvanceController()
        ctrl.playNow(makeTracks(count: 3), startAt: 0)
        ctrl.isPlaying = false // pause keeps the selection, clears the on-deck
        ctrl.pendingNextIndex = nil
        ctrl.playNext(["paused.flac"])
        #expect(ctrl.playlist.count == 4)
        #expect(ctrl.playlist[1] == "paused.flac", "paused Play Next inserts after current, not at the end")
        #expect(ctrl.pendingNextIndex == nil, "paused → not armed; resume re-primes")
    }

    @Test("VM-Q-10: playNext on the last track inserts at the end and arms it")
    func playNextAtLastTrack() {
        let ctrl = MockAdvanceController()
        ctrl.playNow(makeTracks(count: 2), startAt: 0)
        ctrl.engineTransitionCount = 1
        ctrl.tick() // advance to the last track
        #expect(ctrl.selectedTrackIndex == 1)
        ctrl.playNext(["end.flac"])
        #expect(ctrl.playlist.count == 3)
        #expect(ctrl.playlist[2] == "end.flac")
        #expect(ctrl.pendingNextIndex == 2)
        #expect(ctrl.lastNextTrackURL == "end.flac")
    }

    @Test("VM-Q-11: append / playNext dedupe a track already in the queue")
    func dedupeOnAdd() {
        let ctrl = MockAdvanceController()
        ctrl.playNow(makeTracks(count: 3), startAt: 0) // track0/1/2.flac
        ctrl.appendToQueue(["track1.flac", "brandnew.flac"]) // track1 is a dup → dropped
        #expect(ctrl.playlist.count == 4)
        #expect(ctrl.playlist.contains("brandnew.flac"))
        #expect(ctrl.playlist.filter { $0 == "track1.flac" }.count == 1)
        let countBefore = ctrl.playlist.count
        ctrl.playNext(["track0.flac"]) // already queued → deduped to empty → no-op
        #expect(ctrl.playlist.count == countBefore)
    }

    @Test("VM-Q-12: empty input is a no-op for all three verbs")
    func emptyInputNoOp() {
        let ctrl = MockAdvanceController()
        ctrl.playNow(makeTracks(count: 2), startAt: 0)
        let before = ctrl.playlist
        ctrl.playNow([])
        ctrl.playNext([])
        ctrl.appendToQueue([])
        #expect(ctrl.playlist == before)
    }
}
