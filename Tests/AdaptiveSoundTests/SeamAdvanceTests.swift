@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - What the view model makes of a gapless seam (VM-AA seam)

//
// The shipped `AudioViewModel`: against `OnDeckEngineModel` (`Rig`) where the engine seams into what was
// armed, and against `FakeEngine` (`FakePlayer`) where the test sets the seam count the engine reports —
// a count that jumps by two in one tick is an input no single-slot engine produces on its own.

@MainActor
@Suite("Gapless seams on the real view model (VM-AA seam)", .timeLimit(.minutes(3)), .attachingLogTail)
struct SeamAdvanceTests {
    /// A real file of ~0.3 s (`Tests/Fixtures/artwork-audio/README.md`), so the length the view model reads
    /// after a seam is a length, not the 0 of a file that does not exist.
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/artwork-audio/fixture.m4a")

    @Test("VM-AA-14/15: after a seek mid-song, the seam still starts the next song's scrubber at 0:00")
    func aSeamAfterASeekStartsAtTheTop() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        rig.vm.duration = 200
        rig.vm.seek(to: 45)
        try await rig.settle()
        #expect(rig.vm.playbackPosition == 45)
        rig.engine.trackEnds()
        rig.tick()
        #expect(rig.vm.selectedTrackIndex == 1, "the seam advanced despite the seek")
        #expect(rig.vm.playbackPosition == 0, "the new song starts at 0:00, not where the seek left the old one")
        #expect(rig.vm.isPlaying)
    }

    @Test("VM-AA-16: at a seam the length is zeroed at once, then read from the new song's file")
    func theLengthIsZeroedThenReadForTheNewSong() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        let song = AudioFile(name: "fixture", relativePath: "", absoluteURL: Self.fixture, format: "M4A",
                             durationSeconds: 0, trackID: 99)
        rig.vm.queue[2] = QueueItem(file: song) // armed after the first seam
        try await rig.endTrackAndFollow()
        try await rig.vm.settled() // t1's length (a file that does not exist: 0) has been read
        #expect(rig.engine.armed == Self.fixture, "\(rig.state)")
        rig.vm.duration = 180 // as if t1 were three minutes long
        rig.engine.trackEnds()
        rig.tick()
        #expect(rig.vm.selectedTrackIndex == 2)
        #expect(rig.vm.duration == 0, "the old song's length was still shown after the seam")
        try await until("the new song's length to be read from its file") { rig.vm.duration > 0 }
        #expect(rig.vm.duration < 1, "the fixture is ~0.3 s; read \(rig.vm.duration) s")
    }

    @Test("VM-AA-17: a seam goes to the armed slot, whatever it is, and sends no start")
    func aSeamGoesToTheArmedSlotWithoutAStart() async throws {
        let rig = try await Rig.playing(tracks: 4, pure: false)
        rig.vm.armOnDeck(index: 2) // the one producer of on-deck requests (Play Next, an edit, …)
        try await rig.settle()
        rig.engine.drain()
        #expect(rig.engine.armed == track(2))
        rig.engine.trackEnds()
        rig.tick()
        #expect(rig.vm.selectedTrackIndex == 2, "the seam went into the armed t2, not the song after t0")
        #expect(rig.vm.pendingNextIndex == 3)
        try await rig.quiesce()
        #expect(rig.engine.heard == [.start(track(0)), .seam(track(2))], "a seam is not a start: \(rig.state)")
    }

    @Test("VM-AA-19: a seam count that jumps by two in one tick advances one song, re-arms, and is taken once")
    func aCountThatJumpsByTwoAdvancesOnce() async throws {
        let player = try await FakePlayer.launched(tracks: 4)
        try await player.play(at: 0)
        #expect(player.vm.pendingNextIndex == 1)
        player.engineReports(position: 0, transitionCount: 2) // two very short songs between two ticks
        try player.tick()
        #expect(player.vm.selectedTrackIndex == 1, "a +2 jump advances to the armed song, one step")
        #expect(player.vm.pendingNextIndex == 2)
        try await player.vm.settled()
        let requests = player.engine.state.withLock(\.nextTracks)
        #expect(requests.last == .some(track(2)), "the new on-deck request: \(requests)")
        try player.tick()
        #expect(player.vm.selectedTrackIndex == 1, "the same count advanced again")
        try await player.vm.settled()
        #expect(player.engine.state.withLock(\.nextTracks) == requests, "a second request for the same count")
    }
}
