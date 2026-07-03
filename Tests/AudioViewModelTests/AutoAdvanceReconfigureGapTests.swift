import Testing

// MARK: - Reconfigure-gap advance and device-loss tests (VM-AA-RGAP, VM-AA-RTR)

@Suite("AudioViewModel — reconfigure-gap and device-loss advance (VM-AA-gap)")
struct AutoAdvanceReconfigureGapTests {
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

    // MARK: VM-AA-RTR-1: track ends before VM armed next — regression target

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

    @Test("VM-AA-RTR-1: track ends before a seamless seam — engine reports ended, VM ADVANCES (reconfigure gap)")
    func trackEndsBeforeSeamlessSeamAdvances() {
        // KI-001 (docs/product/known-issues.md), RESOLVED: a very short current track can end
        // before the engine armed the next track for a SEAMLESS seam, so the engine reports
        // playbackEnded with no transition. The VM must CONTINUE to the queued next track via a
        // fresh start — a brief, honest reconfigure gap — NOT stop mid-playlist. This continue
        // behavior is provided by tickSpectrum()'s `playbackEnded → advance to pendingNextIndex`
        // branch (pendingNextIndex is always set mid-playlist; it is nil only at end-of-playlist,
        // which is the one case that legitimately stops). Seamless (gapless) advance for
        // arbitrarily-short tracks is a separate enhancement: it needs an engine-side 2-deep
        // on-deck queue (a single slot can't arm track C until B is current at the seam).

        let engine = MockAudioEngine()

        // The engine reaches EOF with no on-deck track armed for a seamless seam → endedFlag,
        // no transition. (A fresh MockAudioEngine already has endedFlag == false.)
        engine.simulateTrackEnd()

        #expect(engine.endedFlag == true,
                "Engine must set endedFlag when a track ends without a seamless seam")
        #expect(engine.transitionCount == 0,
                "transitionCount must NOT increment when no gapless seam occurred")

        // The VM's tick sees endedFlag == true with a track still queued (pendingNextIndex set)
        // and ADVANCES to it via a fresh start rather than stopping. (Modelled via
        // MockAdvanceController, which mirrors tickSpectrum()'s auto-advance logic exactly.)
        let ctrl = MockAdvanceController()
        ctrl.playlist = makeTracks(count: 3)
        ctrl.playTrack(at: 0) // arms pendingNextIndex = 1
        ctrl.engineEndedFlag = true // current track ended with 1 still on deck (no seamless seam)
        ctrl.tick()

        #expect(ctrl.isPlaying == true,
                "VM must CONTINUE (advance to the queued track) when a track ends before a seamless seam")
        #expect(ctrl.selectedTrackIndex == 1,
                "VM must advance selection to the queued next track (not stop)")
        #expect(ctrl.startPlaybackCallCount == 2,
                "the advance is a fresh start of the queued track (initial play + one advance)")
    }
}
