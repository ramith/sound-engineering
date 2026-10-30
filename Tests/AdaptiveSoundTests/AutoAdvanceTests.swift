@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Auto-advance: linear, repeat, shuffle, a failed start, the path (VM-AA)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel` (`Rig`): the engine seams into the song the
// view model armed, or reports the end when nothing is armed, and the view model's tick follows. These
// were the state-machine mirror's cases (`MockAdvanceController`, retired): the same behaviours, now of
// the code that ships. Each runs on both paths where the engine's arming differs (Pure opens the pick).

@MainActor
@Suite("Auto-advance on the real view model (VM-AA)", .timeLimit(.minutes(3)), .attachingLogTail)
struct AutoAdvanceTests {
    @Test("VM-AA-01: one song, no repeat — nothing is armed, and at its end the queue stops on it",
          arguments: [false, true])
    func oneSongStopsAtItsEnd(pure: Bool) async throws {
        let rig = try await Rig.playing(tracks: 1, pure: pure)
        #expect(rig.vm.pendingNextIndex == nil, "nothing follows the only song")
        #expect(rig.engine.armed == nil)
        try await rig.endTrackAndFollow()
        #expect(!rig.vm.isPlaying, "the end of the queue stops")
        #expect(rig.vm.playbackPosition == 0)
        #expect(rig.vm.selectedTrackIndex == 0, "the last song stays selected")
        #expect(rig.engine.current == nil, "the engine is stopped for real (S10.8 G): \(rig.state)")
        #expect(rig.engine.heard == [.start(track(0))])
    }

    @Test("VM-AA-02: a seam mid-queue selects the armed song, puts the scrubber at the top and arms the next",
          arguments: [false, true])
    func seamAdvancesToTheArmedSong(pure: Bool) async throws {
        let rig = try await Rig.playing(tracks: 3, pure: pure)
        #expect(rig.vm.pendingNextIndex == 1)
        #expect(rig.engine.armed == track(1))
        rig.engine.trackEnds()
        rig.tick()
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.vm.playbackPosition == 0, "the scrubber starts the new song at 0:00")
        #expect(rig.vm.pendingNextIndex == 2)
        try await rig.settle()
        rig.engine.drain()
        #expect(rig.engine.armed == track(2), "the next song is armed: \(rig.state)")
        #expect(rig.engine.heard == [.start(track(0)), .seam(track(1))])
        #expect(rig.vm.isPlaying)
    }

    @Test("VM-AA-03: the last song's end, no repeat — the queue stops and the last song stays selected",
          arguments: [false, true])
    func lastSongStopsAndStaysSelected(pure: Bool) async throws {
        let rig = try await Rig.playing(tracks: 2, pure: pure)
        try await rig.endTrackAndFollow()
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.vm.pendingNextIndex == nil, "nothing after the last song")
        try await rig.endTrackAndFollow()
        #expect(!rig.vm.isPlaying)
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.engine.current == nil, "\(rig.state)")
    }

    @Test("VM-AA-04: repeat all — after the last song the first plays, and playback goes on",
          arguments: [false, true])
    func repeatAllWrapsToTheFirstSong(pure: Bool) async throws {
        let rig = try await Rig.playing(tracks: 3, pure: pure, repeatMode: 1)
        try await rig.endTrackAndFollow()
        try await rig.endTrackAndFollow()
        #expect(rig.vm.selectedTrackIndex == 2)
        #expect(rig.vm.pendingNextIndex == 0, "repeat all arms the first song after the last")
        #expect(rig.engine.armed == track(0))
        try await rig.endTrackAndFollow()
        #expect(rig.vm.selectedTrackIndex == 0)
        #expect(rig.vm.isPlaying)
        #expect(rig.engine.current == track(0) && rig.shown == track(0), "\(rig.state)")
    }

    @Test("VM-AA-05: repeat one — the same song is armed, and plays again", arguments: [false, true])
    func repeatOneReplaysTheSameSong(pure: Bool) async throws {
        let rig = try await Rig.playing(tracks: 3, at: 1, pure: pure, repeatMode: 2)
        #expect(rig.vm.pendingNextIndex == 1, "repeat one arms the song that plays")
        #expect(rig.engine.armed == track(1))
        try await rig.endTrackAndFollow()
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.vm.pendingNextIndex == 1)
        #expect(rig.vm.isPlaying)
        #expect(rig.engine.heard == [.start(track(1)), .seam(track(1))], "\(rig.state)")
    }

    /// A refused start moves on to the next song since the founder's "Move on" (break-it LOW-4, 2026-10-30;
    /// VM-UQ in UnplayableQueueTests): this pins the case with nothing to move on to — the last song, no repeat.
    @Test("VM-AA-08: a start the engine refuses with no song after it says so, stops, and arms nothing")
    func aStartThatFailsSaysSoAndStops() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false, unreadable: [track(2)])
        rig.vm.playTrack(at: 2)
        try await rig.quiesce()
        #expect(rig.vm.errorMessage?.hasPrefix("Playback failed") == true, "\(rig.vm.errorMessage ?? "no error")")
        #expect(!rig.vm.isPlaying)
        #expect(rig.vm.pendingNextIndex == nil)
        #expect(rig.vm.selectedTrackIndex == 2, "the song the user asked for stays selected")
        #expect(rig.engine.current == nil, "\(rig.state)")
    }

    @Test("VM-AA-09: shuffle — every song that ends is followed by another song, the one that was armed")
    func shuffleNeverRepeatsTheSongThatEnded() async throws {
        let rig = try await Rig.playing(tracks: 5, pure: false, shuffle: true, repeatMode: 1)
        var visited: Set = [0]
        for _ in 0 ..< 10 {
            let ended = try #require(rig.vm.selectedTrackIndex)
            let armed = try #require(rig.vm.pendingNextIndex, "shuffle with repeat all always has a next song")
            #expect(armed != ended, "shuffle armed the song that plays: \(armed)")
            #expect((0 ..< 5).contains(armed))
            try await rig.endTrackAndFollow()
            #expect(rig.vm.selectedTrackIndex == armed, "the seam went into the armed song")
            #expect(rig.engine.current == rig.shown, "\(rig.state)")
            visited.insert(armed)
        }
        #expect(visited.count > 1, "shuffle visited \(visited)")
    }

    @Test("VM-AA-10: a seam is taken once — a second tick on the same count changes nothing")
    func aSeamIsTakenOnce() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        rig.engine.trackEnds()
        rig.tick()
        #expect(rig.vm.selectedTrackIndex == 1)
        try await rig.settle()
        rig.engine.drain()
        let requests = rig.vm.onDeckSequence
        rig.tick()
        #expect(rig.vm.selectedTrackIndex == 1, "the same seam was taken twice")
        #expect(rig.vm.onDeckSequence == requests, "a second request for the same seam")
        #expect(rig.engine.heard == [.start(track(0)), .seam(track(1))])
    }

    @Test("VM-AA-11/12: the advance plays on the path the user asked for — Pure, or Enhanced",
          arguments: [true, false])
    func theAdvancePlaysOnThePathAsked(pure: Bool) async throws {
        // On Pure t1 can't join gaplessly (another rate): the end, then a fresh start of t1 (the
        // reconfigure gap). On Enhanced it seams in. Either way t1 plays on the path asked for.
        let rig = try await Rig.playing(tracks: 3, pure: pure, incompatible: [track(1)])
        #expect(rig.engine.playsPure == pure)
        try await rig.endTrackAndFollow()
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.vm.isPlaying)
        #expect(rig.engine.current == track(1))
        #expect(rig.engine.playsPure == pure, "t1 plays on \(rig.engine.playsPure ? "Pure" : "Enhanced")")
        let intoT1: OnDeckEngineModel.Heard = pure ? .start(track(1)) : .seam(track(1))
        #expect(rig.engine.heard == [.start(track(0)), intoT1], "\(rig.state)")
    }
}
