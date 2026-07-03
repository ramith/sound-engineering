import Testing

// MARK: - Gapless seam, position, and transition-count tests (VM-AA-14 – VM-AA-19)

@Suite("AudioViewModel — gapless seam correctness (VM-AA-seam)")
struct AutoAdvanceGaplessSeamTests {
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
}
