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

    @Test("VM-AA-RTR-1: track ends before VM arms next — engine reports ended, VM stops (regression target)")
    func trackEndsBeforeVMArmsSetsEndedFlag() {
        // NOTE: This test documents the CURRENT behaviour: the VM stops rather than advancing.
        // A future architectural fix (pre-arm or engine-side look-ahead) should invert the
        // final `isPlaying` assertion to `true` and the `endedFlag` assertion to `false`.

        let engine = MockAudioEngine()

        // 3-track playlist; we will fire track-end BEFORE the VM has called setNextTrack.
        // Simulate: VM starts track 0, but before it can call setNextTrack the engine reaches EOF.
        // (A fresh MockAudioEngine already has endedFlag == false; no reset needed.)

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

        // KNOWN ISSUE KI-001 (docs/product/known-issues.md): a short track can reach EOF
        // before the VM arms the next track, and the player stalls instead of advancing.
        // The desired behavior (continue/advance) is pending a product decision + fix; this
        // assertion documents the CURRENT (defective) behavior. Wrapped in withKnownIssue so
        // the suite stays green while tracked — when the fix lands this stops reproducing and
        // the test fails, prompting removal of the wrapper and a corrected assertion.
        withKnownIssue("KI-001: short-track auto-advance gap — VM stalls instead of advancing") {
            #expect(ctrl.isPlaying == false,
                    "VM must stop when engine signals ended with no next track armed (short-track gap regression)")
        }
    }
}
