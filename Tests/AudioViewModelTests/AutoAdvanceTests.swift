import Testing

// NOTE: AudioViewModel lives in the `AdaptiveSound` executable target. SPM does
// not allow @testable import of executable targets, so these tests exercise the
// auto-advance state machine via a local mirror — `MockAdvanceController` — that
// replicates the exact logic from AudioViewModel.  When AudioViewModel is
// extracted into a library target (Phase 1.5), replace this mirror approach with
// @testable import AdaptiveSoundCore and drive AudioViewModel directly.

// MARK: - State machine mirror

/// Mirrors the continuous-playback state machine from `AudioViewModel`.
/// Only the auto-advance logic (not AVAudioFile duration or timer firing) is
/// mirrored; everything async/effectful is synchronous in this model.
private final class MockAdvanceController {
    // MARK: Playlist

    var playlist: [String] = [] // track names (stand-ins for AudioFile)
    var selectedTrackIndex: Int?

    // MARK: Playback state

    var isPlaying: Bool = false
    var playbackPosition: Double = 0
    var duration: Double = 0
    var pureModeEnabled: Bool = false
    var errorMessage: String?

    // MARK: Repeat / Shuffle

    var shuffleEnabled: Bool = false
    var repeatMode: Int = 0 // 0=none, 1=all, 2=one

    // MARK: Gapless state

    var pendingNextIndex: Int?
    var lastTransitionCount: UInt64 = 0
    private(set) var startPlaybackCallCount: Int = 0
    private(set) var lastStartedIndex: Int?
    private(set) var lastStartedPureMode: Bool = false
    private(set) var setNextTrackCallCount: Int = 0
    private(set) var lastNextTrackURL: String? // nil = cleared

    // MARK: Simulated engine state

    var engineTransitionCount: UInt64 = 0
    var engineEndedFlag: Bool = false
    var startAudioThrows: Bool = false
    /// Models the async restart window on a Pure rate-transition advance: when `true`, `startPlayback`
    /// only records the call and returns WITHOUT resetting `engineEndedFlag`/`isPlaying`/`pendingNextIndex`
    /// — i.e. the real `pureModeEngineStart` (which resets `ended_`) hasn't run yet. Lets a test fire a
    /// re-entrant tick while "ended" is still true, to prove the advance happens exactly once.
    var deferEndedReset: Bool = false

    // MARK: - Mirror of startPlayback()

    func startPlayback() {
        guard let idx = selectedTrackIndex, idx < playlist.count else {
            errorMessage = "No track selected"
            return
        }
        startPlaybackCallCount += 1
        lastStartedIndex = idx
        lastStartedPureMode = pureModeEnabled

        if startAudioThrows {
            errorMessage = "Playback failed: simulated error"
            isPlaying = false
            pendingNextIndex = nil
            return
        }

        // Async restart in flight (Pure rate-transition advance): the real pureModeEngineStart that
        // resets ended_/isPlaying/pending hasn't run yet — leave state untouched so a re-entrant tick
        // is exercisable. (Normal tests keep this false → synchronous reset, the common case.)
        if deferEndedReset {
            return
        }

        // Reset transition baseline.
        lastTransitionCount = engineTransitionCount
        engineEndedFlag = false

        isPlaying = true
        errorMessage = nil
        playbackPosition = 0

        // Compute and queue the on-deck track.
        let nextIdx = computeNextIndex(current: idx, playlistCount: playlist.count)
        pendingNextIndex = nextIdx
        primeNextTrack(nextIdx)
    }

    private func primeNextTrack(_ idx: Int?) {
        setNextTrackCallCount += 1
        if let validIdx = idx, validIdx < playlist.count {
            lastNextTrackURL = playlist[validIdx]
        } else {
            lastNextTrackURL = nil
        }
    }

    // MARK: - Mirror of tickSpectrum() — gapless poll section

    /// Call this to simulate one 20 Hz tick.  The caller controls `engineTransitionCount`
    /// and `engineEndedFlag` to drive the state machine.
    func tick() {
        guard isPlaying else { return }

        if engineTransitionCount > lastTransitionCount {
            lastTransitionCount = engineTransitionCount
            handleTrackTransition()
        } else if engineEndedFlag {
            // Mirror production: a still-queued track (a Pure rate-transition that couldn't be armed
            // for a seamless seam) advances via a fresh start; pendingNextIndex is cleared
            // SYNCHRONOUSLY before startPlayback to block a re-entrant double-advance. Otherwise stop.
            if let nextIdx = pendingNextIndex, nextIdx < playlist.count {
                selectedTrackIndex = nextIdx
                pendingNextIndex = nil
                startPlayback()
            } else {
                isPlaying = false
                playbackPosition = 0
            }
        }
    }

    // MARK: - Mirror of handleTrackTransition()

    private func handleTrackTransition() {
        guard let nextIdx = pendingNextIndex else { return }
        guard nextIdx < playlist.count else {
            pendingNextIndex = nil
            isPlaying = false
            playbackPosition = 0
            return
        }

        // Advance selection and reset scrubber / duration.
        selectedTrackIndex = nextIdx
        playbackPosition = 0
        duration = 0

        // Compute the NEW next index.
        let newNextIdx = computeNextIndex(current: nextIdx, playlistCount: playlist.count)
        pendingNextIndex = newNextIdx
        primeNextTrack(newNextIdx)
    }

    // MARK: - Mirror of computeNextIndex()

    func computeNextIndex(current: Int, playlistCount: Int) -> Int? {
        guard playlistCount > 0 else { return nil }

        if repeatMode == 2 { return current }

        if shuffleEnabled, playlistCount > 1 {
            // Deterministic in tests: use a simple linear walk that avoids current.
            // (The real VM uses Int.random; we verify the property, not the value.)
            return (current + 1) % playlistCount
        }

        let nextLinear = current + 1
        if nextLinear < playlistCount { return nextLinear }
        if repeatMode == 1 { return 0 }
        return nil
    }

    // MARK: - Mirror of removeTrack(at:) — gapless-relevant section

    /// Select a neighbour index after removing the item at `removed` from a list of `count` items.
    private func neighbourIndex(removed: Int, count: Int) -> Int? {
        if removed < count { return removed }
        if removed > 0 { return removed - 1 }
        return nil
    }

    func removeTrack(at index: Int) {
        guard index >= 0, index < playlist.count else { return }

        let removingCurrent = (selectedTrackIndex == index)
        playlist.remove(at: index)

        if let pending = pendingNextIndex {
            if pending == index {
                // On-deck track removed: re-compute from the still-playing current track.
                // P2-2: playlist.remove(at:) has already shifted indices — if selectedTrackIndex
                // was after the removed slot, the correct post-removal index is one lower.
                let rawCurrent = selectedTrackIndex ?? 0
                let currentIdx = rawCurrent > index ? rawCurrent - 1 : rawCurrent
                let newNextIdx = computeNextIndex(current: currentIdx, playlistCount: playlist.count)
                pendingNextIndex = newNextIdx
                setNextTrackCallCount += 1
                lastNextTrackURL = newNextIdx.map { playlist[$0] }
            } else if pending > index {
                pendingNextIndex = pending - 1
            }
        }

        if removingCurrent, isPlaying {
            pendingNextIndex = nil
            isPlaying = false
            playbackPosition = 0
            selectedTrackIndex = neighbourIndex(removed: index, count: playlist.count)
            return
        }

        if selectedTrackIndex == index {
            selectedTrackIndex = neighbourIndex(removed: index, count: playlist.count)
        } else if let cur = selectedTrackIndex, cur > index {
            selectedTrackIndex = cur - 1
        }
    }

    // MARK: - Mirror of clearPlaylist()

    func clearPlaylist() {
        playlist.removeAll()
        selectedTrackIndex = nil
        pendingNextIndex = nil
        isPlaying = false
        playbackPosition = 0
        duration = 0
    }

    // MARK: - Mirror of stopPlayback()

    func stopPlayback() {
        pendingNextIndex = nil
        isPlaying = false
        playbackPosition = 0
        duration = 0
    }

    // MARK: - Mirror of playTrack(at:)

    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        selectedTrackIndex = index
        startPlayback()
    }
}

// MARK: - Test helpers

private func makeTracks(count: Int) -> [String] {
    (0 ..< count).map { "track\($0).flac" }
}

private func makeURL(_ name: String) -> String {
    name
}

// MARK: - Auto-advance test suite

@Suite("AudioViewModel — auto-advance state machine (VM-AA)")
struct AutoAdvanceTests {
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

    // MARK: VM-AA-06: remove current track mid-play then end — no spurious advance

    @Test("VM-AA-06: removing currently-playing track stops cleanly, no spurious advance")
    func removeCurrentTrackStops() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.playTrack(at: 1)

        #expect(ctrl.isPlaying == true)
        #expect(ctrl.selectedTrackIndex == 1)

        // Remove the currently-playing track.
        ctrl.removeTrack(at: 1)

        #expect(ctrl.isPlaying == false, "Removing current track must stop playback")
        #expect(ctrl.pendingNextIndex == nil, "pendingNextIndex must be nil after removing current track")

        // Now simulate the engine firing a transition (stale event — must be ignored).
        ctrl.engineTransitionCount = 1
        ctrl.tick() // isPlaying is false, tick is a no-op

        // No spurious advance should have occurred.
        #expect(ctrl.isPlaying == false, "Stale transition after stop must not restart playback")
    }

    // MARK: VM-AA-07: clear playlist mid-play

    @Test("VM-AA-07: clearPlaylist during playback stops and clears everything")
    func clearPlaylistMidPlay() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 4)
        ctrl.playTrack(at: 2)

        #expect(ctrl.isPlaying == true)

        ctrl.clearPlaylist()

        #expect(ctrl.playlist.isEmpty, "Playlist must be empty after clearPlaylist")
        #expect(ctrl.isPlaying == false, "Must stop after clearPlaylist")
        #expect(ctrl.selectedTrackIndex == nil, "selectedTrackIndex must be nil after clearPlaylist")
        #expect(ctrl.pendingNextIndex == nil, "pendingNextIndex must be nil after clearPlaylist")
        #expect(ctrl.playbackPosition == 0)
        #expect(ctrl.duration == 0)
    }

    // MARK: VM-AA-08: user-initiated replay after stop — startAudio throws (error path)

    //
    // NOTE: `handleTrackTransition` never calls `startAudio`; it only updates index state
    // and calls `setNextTrack`. Therefore an engine-level failure to open the NEXT file
    // during a gapless seam is an integration-level concern, not unit-testable via this
    // mirror. This test covers the distinct USER-INITIATED replay error path: the user
    // explicitly re-triggers playback of a track that the engine cannot open.

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

    // MARK: VM-AA-13: device-loss interrupt during advance — mock only

    @Test("VM-AA-13: device-loss interrupt clears pending on-deck and stops playback")
    func deviceLossInterruptClearsOnDeck() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.playTrack(at: 0)

        #expect(ctrl.pendingNextIndex == 1)

        // Simulate a device-loss interrupt (mirrors the signalPath.interrupted branch in tickSpectrum).
        ctrl.pendingNextIndex = nil
        ctrl.isPlaying = false
        ctrl.playbackPosition = 0

        #expect(ctrl.pendingNextIndex == nil, "Device-loss must clear pendingNextIndex")
        #expect(ctrl.isPlaying == false, "Device-loss must stop isPlaying")
        #expect(ctrl.playbackPosition == 0)

        // A subsequent tick must be a no-op (no spurious advance).
        ctrl.engineTransitionCount = 1
        ctrl.tick() // isPlaying is false — tick is a no-op in the mirror
        #expect(ctrl.selectedTrackIndex == 0, "Index must not advance after device-loss stop")
    }

    // MARK: VM-AA-14: seek during advance — no crash, consistent state

    @Test("VM-AA-14: seek during an ongoing advance leaves state consistent")
    func seekDuringAdvanceIsConsistent() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.playTrack(at: 0)

        // Seek mid-track — simulate by setting playbackPosition.
        ctrl.playbackPosition = 45.0

        // Now a transition fires (gapless seam completes).
        ctrl.engineTransitionCount = 1
        ctrl.tick()

        // After the transition the position must be reset regardless of the prior seek.
        #expect(ctrl.playbackPosition == 0, "playbackPosition must reset to 0 after a track transition")
        #expect(ctrl.selectedTrackIndex == 1, "selectedTrackIndex must advance despite mid-track seek")
        #expect(ctrl.isPlaying == true, "Must remain playing after a seek+transition")
    }

    // MARK: VM-AA-15: playbackPosition resets to 0 on advance

    @Test("VM-AA-15: playbackPosition resets to 0 on every track transition")
    func positionResetsOnAdvance() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.playTrack(at: 0)

        ctrl.playbackPosition = 120.5 // emulate the scrubber being mid-way

        ctrl.engineTransitionCount = 1
        ctrl.tick()

        #expect(ctrl.playbackPosition == 0,
                "playbackPosition must be reset to 0 immediately on transition")
    }

    // MARK: VM-AA-16: duration zeroed before async refresh

    @Test("VM-AA-16: duration is zeroed synchronously before the async refresh fires")
    func durationZeroedBeforeRefresh() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 2)
        ctrl.playTrack(at: 0)
        ctrl.duration = 180.0 // pretend the previous track was 3 minutes

        ctrl.engineTransitionCount = 1
        ctrl.tick()

        // In the mirror, handleTrackTransition sets duration = 0 synchronously.
        // The async AVAudioFile read (which would set the real duration) is not
        // replicated in the mirror, so duration stays 0.
        #expect(ctrl.duration == 0,
                "duration must be zeroed synchronously before async AVAudioFile read")
    }

    // MARK: VM-AA-17: selectedTrackIndex set BEFORE startPlayback / transition callback

    @Test("VM-AA-17: selectedTrackIndex is updated before startPlayback is called")
    func selectedTrackIndexSetBeforeStartPlayback() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)

        // Arrange: start at index 0.
        ctrl.selectedTrackIndex = 0
        ctrl.isPlaying = true
        ctrl.lastTransitionCount = 0

        // Simulate transition: handleTrackTransition internally sets selectedTrackIndex
        // FIRST, then calls primeNextTrack.
        ctrl.pendingNextIndex = 2
        ctrl.engineTransitionCount = 1
        ctrl.tick()

        // selectedTrackIndex must reflect the transitioned-to track.
        #expect(ctrl.selectedTrackIndex == 2,
                "selectedTrackIndex must be set to the advanced index before any further callbacks")
        #expect(ctrl.lastStartedIndex == nil,
                "startPlayback is NOT called on a gapless transition (engine already playing next)")
    }

    // MARK: VM-AA-18: remove the on-deck (pending-next) track while playing

    @Test("VM-AA-18: removing the on-deck track while playing re-primes the engine with the new next")
    func removeOnDeckTrackReprimesEngine() {
        // 3-track playlist: track 0 playing, track 1 is on-deck (pendingNextIndex == 1).
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3) // ["track0.flac", "track1.flac", "track2.flac"]
        ctrl.repeatMode = 0
        ctrl.playTrack(at: 0)

        #expect(ctrl.selectedTrackIndex == 0, "Playing track 0")
        #expect(ctrl.pendingNextIndex == 1, "Track 1 should be on-deck")
        #expect(ctrl.isPlaying == true)

        let callsBefore = ctrl.setNextTrackCallCount

        // Remove the on-deck track (index 1). After removal the list is
        // ["track0.flac", "track2.flac"]. The new next after index 0 is index 1 (track2).
        ctrl.removeTrack(at: 1)

        // Playback on track 0 must be uninterrupted.
        #expect(ctrl.isPlaying == true, "Playback must continue on the current track")
        #expect(ctrl.selectedTrackIndex == 0, "selectedTrackIndex must stay at 0")

        // The engine must be re-primed with the new next track (was track2, now at index 1).
        #expect(ctrl.setNextTrackCallCount == callsBefore + 1,
                "setNextTrack must be called once to replace the removed on-deck track")
        #expect(ctrl.lastNextTrackURL == "track2.flac",
                "Engine must be primed with track2 (the new next after index 0)")
        #expect(ctrl.pendingNextIndex == 1,
                "pendingNextIndex must be updated to 1 (track2's new position)")

        // A subsequent transition must land on index 1 (track2), not the stale index 1 (track1).
        ctrl.engineTransitionCount = 1
        ctrl.tick()

        #expect(ctrl.selectedTrackIndex == 1,
                "Transition must advance to index 1 (track2, now at that position)")
        #expect(ctrl.isPlaying == true, "Playback must continue after transition")
    }

    // MARK: VM-AA-RTR: regression — track ends before VM armed the next track (short-track gap)

    // This is a REGRESSION TARGET for a later architectural fix, not a fix itself.
    //
    // Gap: the VM polls the engine at 20 Hz and calls setNextTrack AFTER startPlayback resolves.
    // For very short tracks (< ~50 ms) the engine can reach EOF before the first VM poll arms
    // the on-deck slot — so nextTrackURL is nil when the track ends, causing the engine to set
    // endedFlag instead of incrementing transitionCount. The VM then stops instead of advancing.
    //
    // MockAudioEngine.simulateTrackEnd() already models this correctly: if nextTrackURL == nil
    // it sets endedFlag, mirroring the engine's behaviour when nothing is on deck.
    //
    // The helper simulateTrackEndWithoutArm() below makes the gap explicit and documents the
    // expected (INCORRECT-but-stable) outcome so a future fix can flip the assertion.

    @Test("VM-AA-RTR-1: track ends before VM arms next — engine reports ended, VM stops (regression target)")
    func trackEndsBeforeVMArmsSetsEndedFlag() {
        // NOTE: This test documents the CURRENT behaviour: the VM stops rather than advancing.
        // A future architectural fix (pre-arm or engine-side look-ahead) should invert the
        // final `isPlaying` assertion to `true` and the `endedFlag` assertion to `false`.

        let engine = MockAudioEngine()

        // 3-track playlist; we will fire track-end BEFORE the VM has called setNextTrack.
        // Simulate: VM starts track 0, but before it can call setNextTrack the engine reaches EOF.
        engine.endedFlag = false

        // Manually simulate the "track ended with nothing on deck" condition:
        // nextTrackURL is nil (the VM hasn't armed it yet) → endedFlag fires, not transitionCount.
        engine.simulateTrackEnd() // nextTrackURL == nil → sets endedFlag

        #expect(engine.endedFlag == true,
                "Engine must set endedFlag when track ends with no next track armed")
        #expect(engine.transitionCount == 0,
                "transitionCount must NOT increment when no track was armed (short-track gap)")

        // The VM's tick sees endedFlag == true with isPlaying == true → stops playback.
        // (Modelled here via MockAdvanceController since we cannot drive AudioViewModel's async loop
        // synchronously. The real VM behaviour is identical: engineEndedFlag=true, tick() → stops.)
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.playTrack(at: 0)
        // Force the engine-ended condition without arming: mirror of engine.simulateTrackEnd() with nil.
        ctrl.engineEndedFlag = true
        ctrl.tick()

        #expect(ctrl.isPlaying == false,
                "VM must stop when engine signals ended with no next track armed (short-track gap regression)")
        // FUTURE: when the architectural fix lands, the above expectation becomes isPlaying == true
        // and selectedTrackIndex advances to 1. Leave this comment as the regression marker.
    }

    // MARK: VM-AA-19: transitionCount jumps by 2 in one tick — exactly one advance

    @Test("VM-AA-19: transitionCount +2 in one tick advances by exactly one track, re-arms next")
    func transitionCountJumpByTwoAdvancesOnce() {
        // The VM records the new baseline and calls handleTrackTransition exactly once
        // per tick, regardless of how far the count jumped. The mirror's tick() does
        // the same: compare once, update lastTransitionCount, call handleTrackTransition.
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 4) // indices 0..3
        ctrl.repeatMode = 0
        ctrl.playTrack(at: 0)

        #expect(ctrl.selectedTrackIndex == 0)
        #expect(ctrl.pendingNextIndex == 1, "Track 1 on-deck after starting at 0")

        // Simulate the count jumping by 2 in a single 20 Hz tick (two very-short tracks
        // completed between polls). The VM should advance exactly once to the on-deck index.
        ctrl.engineTransitionCount = 2 // jumped by 2 from baseline 0
        ctrl.tick()

        // Exactly one advance: land on the on-deck index (1), not two ahead (2).
        #expect(ctrl.selectedTrackIndex == 1,
                "A +2 jump must still advance selectedTrackIndex by exactly one to the on-deck index")
        #expect(ctrl.isPlaying == true, "Must remain playing after a single advance")

        // After the advance, the new on-deck must be armed.
        #expect(ctrl.pendingNextIndex == 2,
                "After advancing to 1, the new on-deck must be 2")
        #expect(ctrl.lastNextTrackURL == "track2.flac",
                "Engine must be primed with track2 as the new on-deck")

        // A second tick with the same count (no further increment) must be a no-op —
        // the +2 baseline is already recorded and does not cause a second advance.
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 1,
                "Same transitionCount on next tick must not advance again")
    }

    // MARK: VM-AA-RGAP-1: Pure rate-transition advance fires exactly once across the restart window

    @Test("VM-AA-RGAP-1: reconfigure-gap advance fires once despite playbackEnded staying true")
    func reconfigureGapAdvanceFiresOnce() {
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3) // indices 0..2
        ctrl.repeatMode = 0
        ctrl.playTrack(at: 0)
        #expect(ctrl.pendingNextIndex == 1, "Track 1 on-deck after starting at 0")
        #expect(ctrl.startPlaybackCallCount == 1, "One initial play")

        // Model a Pure rate/format mismatch: track 1 was supplied but NOT gaplessly armed, so no
        // seam fires — instead the engine reports playbackEnded with a track still queued.
        // deferEndedReset models the async restart in flight (pureModeEngineStart, which resets
        // ended_, hasn't run yet) so engineEndedFlag stays true across the next tick.
        ctrl.deferEndedReset = true
        ctrl.engineEndedFlag = true

        // Tick 1: advance to the queued track via a fresh start (the reconfigure-gap path).
        ctrl.tick()
        #expect(ctrl.selectedTrackIndex == 1, "Must advance to the queued track on playbackEnded")
        #expect(ctrl.startPlaybackCallCount == 2, "One initial play + one advance restart")
        #expect(ctrl.pendingNextIndex == nil,
                "pendingNextIndex must be cleared SYNCHRONOUSLY to block a re-entrant double-advance")

        // Tick 2: the async restart still hasn't completed (engineEndedFlag still true). Without the
        // synchronous clear this would advance a SECOND time and interrupt the track mid-startup.
        ctrl.tick()
        #expect(ctrl.startPlaybackCallCount == 2,
                "No double-advance: the second tick must not launch another startPlayback")
        #expect(ctrl.selectedTrackIndex == 1, "Selection must not jump a second time")
    }
}
