@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - A song that can't play, and the queue (break-it LOW-4; founder, 2026-10-30: "Move on") (VM-UQ)

//
// The founder's rule: a song that can't be played — damaged, or a format macOS can't decode — says why in the
// banner, and playback goes on to the next song, whether the listener pressed Play on it or the queue reached it
// (a gapless seam into it included). The song stays in the queue, not removed and not marked. When no song left can
// play (one full pass fails, under Repeat All and in shuffle too), playback stops with the message, and never loops.
//
// The shipped `AudioViewModel` against `OnDeckEngineModel` (`Rig`): a start of an `unreadable` song is refused as the
// bridge refuses a file it can't open or decode; on Pure such a song never arms, so the song before it ends and the
// view model starts it fresh — the bridge's own refusal at an Enhanced seam (`ReaderSeamTests`) ends it the same way.

@MainActor
@Suite("A song that can't play: the banner says why and the queue moves on (VM-UQ, LOW-4)", .timeLimit(.minutes(3)),
       .attachingLogTail)
struct UnplayableQueueTests {
    @Test("VM-UQ-01: Play on a song that can't play says why, and the next song plays; the song stays in the queue")
    func playOnASongThatCannotPlayMovesOn() async throws {
        let rig = try await Rig.playing(tracks: 4, pure: false, unreadable: [track(1)])
        rig.vm.playTrack(at: 1)
        try await rig.quiesce()
        #expect(rig.vm.isPlaying, "\(rig.state)")
        #expect(rig.vm.selectedTrackIndex == 2, "the next song is the one playing")
        #expect(rig.engine.current == track(2), "\(rig.state)")
        #expect(rig.vm.errorMessage?.hasPrefix("Skipped “") == true, "\(rig.vm.errorMessage ?? "no message")")
        #expect(rig.vm.queue.map(\.file.absoluteURL) == (0 ..< 4).map(track), "the song stays in the queue")
        #expect(rig.disagreement == nil, "\(rig.disagreement ?? "")")
    }

    @Test("VM-UQ-02: the queue reaches a song that can't play — the song before ends, then the next one plays")
    func theQueueReachingASongThatCannotPlayMovesOn() async throws {
        // On Pure the pick that won't open never arms, so the song before plays to its end and the view model
        // starts the next song fresh: as the bridge refuses one at an Enhanced seam.
        let rig = try await Rig.playing(tracks: 4, pure: true, unreadable: [track(1)])
        try await rig.endTrackAndFollow()
        try await rig.quiesce()
        #expect(rig.engine.heard == [.start(track(0)), .start(track(2))], "\(rig.state)")
        #expect(rig.vm.isPlaying)
        #expect(rig.vm.selectedTrackIndex == 2)
        #expect(rig.vm.errorMessage?.hasPrefix("Skipped “") == true, "\(rig.vm.errorMessage ?? "no message")")
    }

    @Test("VM-UQ-03: no song can play, Repeat All — one pass of tries, then playback stops with the message",
          arguments: [false, true])
    func aFullPassThatFailsStops(shuffle: Bool) async throws {
        let rig = Rig(tracks: 4, unreadable: Set((0 ..< 4).map(track)))
        rig.vm.shuffleEnabled = shuffle
        rig.vm.repeatMode = 1
        rig.vm.playTrack(at: 0)
        try await rig.quiesce()
        #expect(!rig.vm.isPlaying)
        #expect(rig.vm.errorMessage?.hasPrefix("Playback stopped — no song left in the queue can be played.") == true,
                "\(rig.vm.errorMessage ?? "no message")")
        #expect(rig.vm.pendingNextIndex == nil)
        #expect(rig.vm.queue.count == 4, "every song stays in the queue")
        // Every song was tried, each at most twice (a shuffled pass may open on one the last pass tried), and
        // the run ended: one stop after the starts, and nothing after it.
        let starts = rig.engine.receivedCount - 1
        #expect(starts >= 4 && starts <= 8, "\(starts) starts for 4 songs")
        #expect(rig.engine.heard.isEmpty, "\(rig.state)")
    }

    // The last song with no repeat — nothing to move on to — stops with why: VM-AA-08 (AutoAdvanceTests).

    @Test("VM-UQ-04: under Repeat One a song that can't play moves on, as Next would — it is never retried")
    func repeatOneMovesOn() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false, repeatMode: 2, unreadable: [track(1)])
        rig.vm.playTrack(at: 1)
        try await rig.quiesce()
        #expect(rig.vm.selectedTrackIndex == 2)
        #expect(rig.engine.current == track(2), "\(rig.state)")
        #expect(rig.vm.isPlaying)
    }

    @Test("VM-UQ-06: the banner names a song as the queue shows it — a library song by its title, a loose file by name",
          arguments: [true, false])
    func theBannerNamesTheSongAsTheQueueShowsIt(isLibrarySong: Bool) async throws {
        // Founder, 2026-10-30. A library song's queue name is its tag title (`AudioFile(LibraryTrackDisplay)`, which
        // falls back to the file name); a loose file's is its file name.
        let rig = try await Rig.playing(tracks: 4, pure: false, unreadable: [track(1)])
        rig.vm.queue[1] = QueueItem(file: isLibrarySong
            ? AudioFile(name: "Sunrise over Kerala", relativePath: "", absoluteURL: track(1), format: "FLAC",
                        durationSeconds: 200, trackID: 2)
            : AudioFile(looseFileAt: track(1)))
        rig.vm.playTrack(at: 1)
        try await rig.quiesce()
        #expect(rig.engine.current == track(2), "\(rig.state)")
        let named = isLibrarySong ? "Sunrise over Kerala" : "t1"
        #expect(rig.vm.errorMessage?.hasPrefix("Skipped “\(named)”. ") == true,
                "\(rig.vm.errorMessage ?? "no message")")
    }

    @Test("VM-UQ-05: a later start the listener asks for clears the message of the songs passed")
    func aLaterStartClearsTheMessage() async throws {
        let rig = try await Rig.playing(tracks: 4, pure: false, unreadable: [track(1)])
        rig.vm.playTrack(at: 1)
        try await rig.quiesce()
        #expect(rig.vm.errorMessage != nil)
        rig.vm.playTrack(at: 3)
        try await rig.quiesce()
        #expect(rig.vm.errorMessage == nil)
        #expect(rig.engine.current == track(3))
    }
}
