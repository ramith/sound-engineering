import Testing

// MARK: - Linear advance, repeat, and shuffle tests (VM-AA-01 – VM-AA-12)

@Suite("AudioViewModel — linear/repeat/shuffle advance (VM-AA)")
struct AutoAdvanceLinearRepeatShuffleTests {
    // MARK: VM-AA-01: single track, no repeat — stops, never advances past end

    @Test("VM-AA-01: single track, no-repeat — ends without advance")
    func singleTrackNoRepeatStops() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 1)
        ctrl.repeatMode = 0
        ctrl.playTrack(at: 0)

        #expect(ctrl.isPlaying == true)
        // No next track should be queued for a single-track no-repeat playlist.
        #expect(ctrl.pendingNextIndex == nil, "No next index for single-track no-repeat")
        #expect(ctrl.lastNextTrackURL == nil, "Engine on-deck should be nil for single-track no-repeat")

        // Simulate engine signalling end-of-track (no next track).
        ctrl.engineEndedFlag = true
        ctrl.tick()

        #expect(ctrl.isPlaying == false, "Playback must stop when engine signals ended")
        #expect(ctrl.playbackPosition == 0, "Position must reset to 0 on stop")
        #expect(ctrl.selectedTrackIndex == 0, "Selection must remain at 0 after stop")
    }

    // MARK: VM-AA-02: mid-playlist advance advances index

    @Test("VM-AA-02: mid-playlist advance sets correct next index")
    func midPlaylistAdvanceSetsIndex() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.repeatMode = 0
        ctrl.playTrack(at: 0)

        #expect(ctrl.pendingNextIndex == 1)
        #expect(ctrl.selectedTrackIndex == 0)

        // Simulate a gapless seam: engine advanced to track 1.
        ctrl.engineTransitionCount = 1
        ctrl.tick()

        #expect(ctrl.selectedTrackIndex == 1, "selectedTrackIndex must advance to 1")
        #expect(ctrl.playbackPosition == 0, "playbackPosition must reset to 0 after transition")
        #expect(ctrl.duration == 0, "duration must be zeroed before async refresh")
        #expect(ctrl.pendingNextIndex == 2, "New on-deck must point to index 2")
    }

    // MARK: VM-AA-03: end of last track, no-repeat — stops, stays at last

    @Test("VM-AA-03: end of last track, no-repeat — stops and stays at last index")
    func endOfLastNoRepeatStops() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 2)
        ctrl.repeatMode = 0
        ctrl.playTrack(at: 0)

        // Advance to track 1 (the last).
        ctrl.engineTransitionCount = 1
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 1)
        #expect(ctrl.pendingNextIndex == nil, "No next after last track in no-repeat mode")

        // Engine signals end-of-track with no next on deck.
        ctrl.engineEndedFlag = true
        ctrl.tick()

        #expect(ctrl.isPlaying == false, "Must stop at end of last track")
        #expect(ctrl.selectedTrackIndex == 1, "Must remain at last index after stopping")
    }

    // MARK: VM-AA-04: end of last track, repeat-all — wraps to 0

    @Test("VM-AA-04: end of last track, repeat-all — wraps to index 0")
    func endOfLastRepeatAllWraps() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.repeatMode = 1 // repeat-all
        ctrl.playTrack(at: 0)

        // Advance twice: 0 → 1 → 2
        ctrl.engineTransitionCount = 1
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 1)

        ctrl.engineTransitionCount = 2
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 2)
        // In repeat-all mode, next after index 2 (last) wraps to 0.
        #expect(ctrl.pendingNextIndex == 0, "repeat-all must queue index 0 after last track")

        // One more transition wraps back to 0.
        ctrl.engineTransitionCount = 3
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 0, "repeat-all must wrap selectedTrackIndex to 0")
        #expect(ctrl.isPlaying == true, "Must stay playing in repeat-all mode")
    }

    // MARK: VM-AA-05: repeat-one replays same track

    @Test("VM-AA-05: repeat-one — replays the same track index")
    func repeatOneReplays() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.repeatMode = 2 // repeat-one
        ctrl.playTrack(at: 1)

        #expect(ctrl.pendingNextIndex == 1, "repeat-one must queue the same index")

        // Simulate a gapless seam: the same track starts again.
        ctrl.engineTransitionCount = 1
        ctrl.tick()

        #expect(ctrl.selectedTrackIndex == 1, "repeat-one must keep selectedTrackIndex at 1")
        #expect(ctrl.pendingNextIndex == 1, "repeat-one must keep on-deck at 1 after transition")
        #expect(ctrl.isPlaying == true)
    }

    // MARK: VM-AA-08: user-initiated replay after stop — startAudio throws (error path)

    @Test("VM-AA-08: user-initiated replay — startAudio throws sets errorMessage, stops playback")
    func userInitiatedReplayStartAudioThrows() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 2)
        ctrl.playTrack(at: 0)

        // Arm the throw to simulate an unreadable file on the next explicit startAudio call.
        ctrl.startAudioThrows = true
        ctrl.selectedTrackIndex = 1
        ctrl.startPlayback()

        #expect(ctrl.errorMessage != nil, "errorMessage must be set when startAudio throws")
        #expect(ctrl.isPlaying == false, "isPlaying must be false when startAudio throws")
        #expect(ctrl.pendingNextIndex == nil, "pendingNextIndex must be nil when startAudio fails")
    }

    // MARK: VM-AA-09: shuffle visits >1 distinct index over many advances

    @Test("VM-AA-09: shuffle mode produces at least 2 distinct indices over 10 advances")
    func shuffleVisitsMultipleIndices() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 5)
        ctrl.shuffleEnabled = true
        ctrl.repeatMode = 1 // repeat-all keeps the queue alive

        ctrl.playTrack(at: 0)

        var visitedIndices = Set<Int>()
        visitedIndices.insert(ctrl.selectedTrackIndex ?? 0)

        for tick in 1 ... 10 {
            ctrl.engineTransitionCount = UInt64(tick)
            ctrl.tick()
            if let idx = ctrl.selectedTrackIndex {
                visitedIndices.insert(idx)
            }
        }

        #expect(visitedIndices.count > 1,
                "Shuffle must visit more than 1 distinct index over 10 advances (got \(visitedIndices))")
    }

    // MARK: VM-AA-10: double-fire guard — only one advance per transition increment

    @Test("VM-AA-10: double-fire of same transitionCount is ignored (guard fires once)")
    func doubleFireGuard() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.playTrack(at: 0)

        // First tick: transition fires legitimately.
        ctrl.engineTransitionCount = 1
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 1)

        let countAfterFirstAdvance = ctrl.setNextTrackCallCount

        // Second tick with the SAME transitionCount: must be a no-op.
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 1, "Double-fire must not advance index a second time")
        #expect(ctrl.setNextTrackCallCount == countAfterFirstAdvance,
                "setNextTrack must not be called again for the same transitionCount")
    }

    // MARK: VM-AA-11: Pure mode passed through on advance

    @Test("VM-AA-11: pureMode=true is preserved through the advance pipeline")
    func pureModePassedThroughOnAdvance() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 2)
        ctrl.pureModeEnabled = true
        ctrl.playTrack(at: 0)

        #expect(ctrl.lastStartedPureMode == true, "pureMode must be true on first startPlayback")

        // Simulate transition to next track.
        ctrl.engineTransitionCount = 1
        ctrl.tick()

        // Verify the next track is queued (advancing continued with pureMode=true captured).
        #expect(ctrl.selectedTrackIndex == 1)
        // The on-deck URL is still set (next after 1 for 2-track list is nil in no-repeat).
        #expect(ctrl.lastNextTrackURL == nil, "No further track in 2-track no-repeat after last")
    }

    // MARK: VM-AA-12: pureMode=false preserved

    @Test("VM-AA-12: pureMode=false is preserved through the advance pipeline")
    func pureModeOffPreserved() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.pureModeEnabled = false
        ctrl.playTrack(at: 0)

        #expect(ctrl.lastStartedPureMode == false, "pureMode must be false on start")

        ctrl.engineTransitionCount = 1
        ctrl.tick()

        #expect(ctrl.selectedTrackIndex == 1)
        #expect(ctrl.isPlaying == true)
    }

    // MARK: VM-AA-13..16: manual Next / Previous honour shuffle + repeat (D2 / VM-2)

    // The manual transport buttons route through computeNextIndex(manualSkip:) /
    // computePreviousIndex, so Next/Prev respect shuffle and repeat instead of stepping linearly.

    @Test("VM-AA-13: manual Next under repeat-one STEPS to the next track (does not repeat)")
    func manualNextRepeatOneSteps() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.repeatMode = 2 // repeat-one
        // Auto-advance repeats the same index…
        #expect(ctrl.computeNextIndex(current: 1, playlistCount: 3) == 1,
                "auto advance under repeat-one repeats the current track")
        // …but a manual Next steps forward.
        #expect(ctrl.computeNextIndex(current: 1, playlistCount: 3, manualSkip: true) == 2,
                "manual Next under repeat-one must step to the next track, not repeat")
    }

    @Test("VM-AA-14: manual Next at the last track wraps under repeat-all, stops otherwise")
    func manualNextEndBehaviour() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.repeatMode = 1 // repeat-all
        #expect(ctrl.computeNextIndex(current: 2, playlistCount: 3, manualSkip: true) == 0,
                "manual Next on the last track wraps to 0 under repeat-all")
        ctrl.repeatMode = 0 // no repeat
        #expect(ctrl.computeNextIndex(current: 2, playlistCount: 3, manualSkip: true) == nil,
                "manual Next on the last track is a no-op (nil) with no repeat")
    }

    @Test("VM-AA-15: manual Previous wraps to the last track under repeat-all, stops otherwise")
    func manualPreviousWrap() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.repeatMode = 1 // repeat-all
        #expect(ctrl.computePreviousIndex(current: 0, playlistCount: 3) == 2,
                "Previous on the first track wraps to the last under repeat-all")
        #expect(ctrl.computePreviousIndex(current: 2, playlistCount: 3) == 1,
                "Previous steps back linearly mid-playlist")
        ctrl.repeatMode = 0 // no repeat
        #expect(ctrl.computePreviousIndex(current: 0, playlistCount: 3) == nil,
                "Previous on the first track is a no-op (nil) with no repeat")
    }

    @Test("VM-AA-16: manual Next / Previous under shuffle pick a different index")
    func manualSkipShufflePicksOther() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 5)
        ctrl.shuffleEnabled = true
        let next = ctrl.computeNextIndex(current: 2, playlistCount: 5, manualSkip: true)
        let prev = ctrl.computePreviousIndex(current: 2, playlistCount: 5)
        #expect(next != nil && next != 2, "shuffle Next must pick a different index")
        #expect(prev != nil && prev != 2, "shuffle Previous must pick a different index")
    }
}
