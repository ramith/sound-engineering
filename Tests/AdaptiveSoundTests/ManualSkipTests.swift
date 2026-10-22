@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Next and Previous honour shuffle and repeat (D2 / VM-2)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel` (`Rig`): the transport buttons go through the
// same rule as the auto-advance (`QueueAdvance`, `manualSkip: true`), and while a song plays they start
// the song they land on. A press with nowhere to go sends the engine nothing.

@MainActor
@Suite("Next and Previous on the real view model (VM-AA manual skip)", .timeLimit(.minutes(3)), .attachingLogTail)
struct ManualSkipTests {
    /// Press `skip`, and let everything it sent land.
    private func press(_ rig: Rig, _ skip: (AudioViewModel) -> Void) async throws {
        skip(rig.vm)
        try await rig.quiesce()
    }

    @Test("VM-AA-13 (manual): Next under repeat one steps to the next song (only the auto-advance repeats)")
    func nextUnderRepeatOneSteps() async throws {
        let rig = try await Rig.playing(tracks: 3, at: 1, pure: false, repeatMode: 2)
        try await press(rig) { $0.nextTrack() }
        #expect(rig.vm.selectedTrackIndex == 2)
        #expect(rig.vm.isPlaying)
        #expect(rig.engine.current == track(2), "\(rig.state)")
    }

    @Test("VM-AA-14 (manual): Next on the last song wraps to the first under repeat all, else does nothing",
          arguments: [1, 0])
    func nextOnTheLastSong(repeatMode: Int) async throws {
        let rig = try await Rig.playing(tracks: 3, at: 2, pure: false, repeatMode: repeatMode)
        let commands = rig.vm.transportEpoch
        try await press(rig) { $0.nextTrack() }
        if repeatMode == 1 {
            #expect(rig.vm.selectedTrackIndex == 0)
            #expect(rig.engine.current == track(0), "\(rig.state)")
        } else {
            #expect(rig.vm.selectedTrackIndex == 2, "Next had nowhere to go")
            #expect(rig.vm.transportEpoch == commands, "a press with nowhere to go sent the engine a command")
            #expect(rig.engine.current == track(2), "\(rig.state)")
        }
        #expect(rig.vm.isPlaying)
    }

    @Test("VM-AA-15 (manual): Previous steps back, wraps to the last song under repeat all, else stops at the top",
          arguments: [1, 0])
    func previousSteps(repeatMode: Int) async throws {
        let rig = try await Rig.playing(tracks: 3, at: 2, pure: false, repeatMode: repeatMode)
        try await press(rig) { $0.previousTrack() }
        #expect(rig.vm.selectedTrackIndex == 1, "Previous steps back mid-queue")
        try await press(rig) { $0.previousTrack() }
        #expect(rig.vm.selectedTrackIndex == 0)
        let commands = rig.vm.transportEpoch
        try await press(rig) { $0.previousTrack() }
        if repeatMode == 1 {
            #expect(rig.vm.selectedTrackIndex == 2, "Previous on the first song wraps to the last")
            #expect(rig.engine.current == track(2), "\(rig.state)")
        } else {
            #expect(rig.vm.selectedTrackIndex == 0, "Previous had nowhere to go")
            #expect(rig.vm.transportEpoch == commands, "a press with nowhere to go sent the engine a command")
            #expect(rig.engine.current == track(0), "\(rig.state)")
        }
    }

    @Test("VM-AA-16 (manual): under shuffle, Next and Previous each start another song")
    func shuffleSkipsToAnotherSong() async throws {
        let rig = try await Rig.playing(tracks: 5, at: 2, pure: false, shuffle: true)
        try await press(rig) { $0.nextTrack() }
        let afterNext = try #require(rig.vm.selectedTrackIndex)
        #expect(afterNext != 2 && (0 ..< 5).contains(afterNext), "shuffle Next landed on \(afterNext)")
        #expect(rig.engine.current == rig.shown, "\(rig.state)")
        try await press(rig) { $0.previousTrack() }
        let afterPrevious = try #require(rig.vm.selectedTrackIndex)
        #expect(afterPrevious != afterNext && (0 ..< 5).contains(afterPrevious),
                "shuffle Previous landed on \(afterPrevious)")
        #expect(rig.engine.current == rig.shown, "\(rig.state)")
        #expect(rig.engine.heard.count(where: \.isStart) == 3, "each press started a song: \(rig.engine.heard)")
    }
}
