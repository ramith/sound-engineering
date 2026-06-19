import Testing

// MARK: - Device-loss and playlist-mutation tests (VM-AA-06, VM-AA-07, VM-AA-13, VM-AA-18)

@Suite("AudioViewModel — device-loss and playlist mutation (VM-AA-device)")
struct AutoAdvanceDeviceLossTests {
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
}
