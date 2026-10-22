@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Ends without a seam, a lagging playhead, a lost device, the queue edited under the song

//
// The shipped `AudioViewModel`: against `OnDeckEngineModel` (`Rig`) for what plays next, and against
// `FakeEngine` (`FakePlayer`) where the test sets what the engine reports (a playhead that lags a seek,
// a lost device). These were the state-machine mirror's reconfigure-gap, device-loss and queue-mutation
// cases (`MockAdvanceController`, retired), now on the code that ships.

@MainActor
@Suite("Track ends and interruptions on the real view model (VM-AA end)", .timeLimit(.minutes(3)),
       .attachingLogTail)
struct TrackEndTests {
    @Test("VM-AA-RGAP-1: an end with a song still queued advances once, though the end flag outlives the restart")
    func anEndWithASongQueuedAdvancesOnce() async throws {
        // Pure, and t1 can't join gaplessly: nothing is armed, t0 ends, the view model starts t1 fresh.
        let rig = try await Rig.playing(tracks: 3, pure: true, incompatible: [track(1)])
        #expect(rig.engine.armed == nil)
        rig.engine.trackEnds()
        rig.engine.holdTransport(true) // the restart takes a while (a DAC changing rate)
        let commands = rig.engine.receivedCount
        rig.tick()
        #expect(rig.vm.selectedTrackIndex == 1, "the end advanced to the queued song")
        try await rig.waitUntil("the restart to reach the engine") { rig.engine.heldEpochs.count == 1 }
        rig.tick() // the engine still reports t0's end: the restart has not begun
        #expect(rig.vm.isPlaying, "the second tick stopped the song that is still starting")
        #expect(rig.vm.selectedTrackIndex == 1, "the second tick advanced again")
        try await rig.runViewModelOut()
        #expect(rig.engine.receivedCount == commands + 1, "one restart, not two: \(rig.engine.heldEpochs)")
        rig.engine.holdTransport(false)
        try await rig.quiesce()
        rig.tick()
        #expect(rig.vm.isPlaying)
        #expect(rig.engine.heard == [.start(track(0)), .start(track(1))], "\(rig.state)")
    }

    @Test("VM-AA-RGAP-2: while a seek is on its way the old playhead is ignored; then the engine's is followed")
    func aLaggingPlayheadNeverMovesTheScrubberBack() async throws {
        let player = try await FakePlayer.launched(tracks: 3)
        try await player.play(at: 0)
        player.engineReports(position: 90)
        try player.tick()
        #expect(player.vm.playbackPosition == 90)
        player.vm.duration = 200
        player.vm.seek(to: 30) // the engine is busy (a slow device start): it still reports 1:30
        for _ in 0 ..< 5 {
            try player.tick()
            #expect(player.vm.playbackPosition == 30, "the scrubber jumped back to the old place")
        }
        player.engineReports(position: 30.5) // the engine reached the seek
        try player.tick()
        #expect(player.vm.playbackPosition == 30.5)
        try await player.vm.settled()
        #expect(player.engine.state.withLock(\.seeks) == [30])
    }

    @Test("VM-AA-RTR-1 (KI-001): a song that ends before its next was armed goes on to it with a fresh start")
    func aSongThatEndsBeforeItsNextIsArmedGoesOn() async throws {
        let rig = Rig(tracks: 3)
        rig.vm.playTrack(at: 0)
        try await rig.settle() // the start ran; its request for t1 has not reached the engine yet
        rig.engine.trackEnds() // a very short t0: its end, nothing armed
        rig.engine.drain()
        try await rig.waitUntil("the start to finish its prime") { rig.vm.isPlaying }
        try await rig.follow()
        #expect(rig.vm.selectedTrackIndex == 1, "the queue stopped mid-way")
        #expect(rig.vm.isPlaying)
        #expect(rig.engine.heard == [.start(track(0)), .start(track(1))], "\(rig.state)")
        #expect(rig.vm.pendingNextIndex == 2)
    }

    @Test("VM-AA-06: removing the playing song stops, and a seam the engine made meanwhile is not followed")
    func removingThePlayingSongStops() async throws {
        let rig = try await Rig.playing(tracks: 3, at: 1, pure: false)
        rig.engine.holdTransport(true)
        rig.vm.removeTrack(at: 1)
        try await rig.waitForCommands() // the stop waits on the busy engine
        rig.engine.trackEnds() // t1 seams into the armed t2 before the stop runs
        rig.tick()
        rig.engine.holdTransport(false)
        try await rig.quiesce()
        rig.tick()
        #expect(!rig.vm.isPlaying)
        #expect(rig.vm.pendingNextIndex == nil)
        #expect(rig.vm.selectedTrackIndex == 1, "the song that slid into the row is selected, not played")
        #expect(rig.engine.current == nil, "\(rig.state)")
        #expect(rig.engine.heard.count(where: \.isStart) == 1, "a start after the removal: \(rig.engine.heard)")
    }

    @Test("VM-AA-07: clearing the queue while a song plays stops it and clears everything")
    func clearingTheQueueStopsAndClearsEverything() async throws {
        let rig = try await Rig.playing(tracks: 4, at: 2, pure: false)
        rig.vm.clearPlaylist()
        try await rig.quiesce()
        #expect(rig.vm.queue.isEmpty)
        #expect(!rig.vm.isPlaying)
        #expect(rig.vm.selectedTrackIndex == nil)
        #expect(rig.vm.pendingNextIndex == nil)
        #expect(rig.vm.playbackPosition == 0)
        #expect(rig.vm.duration == 0)
        #expect(rig.engine.current == nil, "\(rig.state)")
    }

    @Test("VM-AA-13 (device loss): a lost device pauses in place and drops the on-deck pick; no later seam moves on")
    func aLostDevicePausesInPlace() async throws {
        let player = try await FakePlayer.launched(tracks: 3)
        try await player.play(at: 0)
        player.vm.duration = 200
        player.engineReports(position: 90)
        try player.tick()
        #expect(player.vm.pendingNextIndex == 1)
        // The headphones went off: the engine paused and says so; it reports no playhead any more.
        player.engine.state.withLock { $0.signalPath.interrupted = true }
        player.engineReports(position: nil)
        try player.tick()
        #expect(!player.vm.isPlaying)
        #expect(player.vm.pausedResumePosition == 90, "Play resumes where the device went")
        #expect(player.vm.playbackPosition == 90, "the scrubber stays put")
        #expect(player.vm.pendingNextIndex == nil, "the on-deck pick goes with the device")
        #expect(player.vm.errorMessage?.contains("disconnected") == true)
        try await player.vm.settled()
        #expect(player.engine.state.withLock(\.nextTracks).last == .some(nil), "the engine was told to drop it")
        #expect(player.bench.current == nil, "paused, the transport tick stops")
        // A seam reported after the pause — a stray tick included — moves nothing.
        player.engineReports(position: 0, transitionCount: 1)
        player.vm.tickTransport()
        #expect(player.vm.selectedTrackIndex == 0)
        #expect(!player.vm.isPlaying)
    }

    @Test("VM-AA-18: removing the on-deck song arms the queue's next, and the seam plays it")
    func removingTheOnDeckSongArmsTheNext() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        #expect(rig.engine.armed == track(1))
        rig.vm.removeTrack(at: 1) // the queue is now t0, t2
        try await rig.settle()
        rig.engine.drain()
        #expect(rig.vm.isPlaying, "playback goes on")
        #expect(rig.vm.selectedTrackIndex == 0)
        #expect(rig.vm.pendingNextIndex == 1)
        #expect(rig.pending == track(2), "the app promises t2")
        #expect(rig.engine.armed == track(2), "the engine was re-armed with t2: \(rig.state)")
        try await rig.endTrackAndFollow()
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.engine.current == track(2) && rig.shown == track(2), "\(rig.state)")
    }
}
