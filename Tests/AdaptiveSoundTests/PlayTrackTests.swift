@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - playTrack(at:): select the song, then start that song (the fix the mirror guarded)

//
// The shipped `AudioViewModel` over `FakeEngine` (`FakePlayer`), which records each start with its file.
// The bug this guards (the selection set after the start, so the start played the stale selection) was
// guarded by a five-line copy of `playTrack(at:)` (`MockPlaylistController`, retired); this is the real one.

@MainActor
@Suite("playTrack(at:) on the real view model", .timeLimit(.minutes(3)), .attachingLogTail)
struct PlayTrackTests {
    private func starts(_ player: FakePlayer) -> [URL] {
        player.engine.state.withLock(\.startedURLs)
    }

    @Test("selects the song asked for and starts that song, once — not the stale selection", arguments: [2, 4, 0])
    func playTrackStartsThatSong(index: Int) async throws {
        let player = try await FakePlayer.launched(tracks: 5)
        player.vm.selectedTrackIndex = index == 0 ? 3 : 0 // a stale selection
        player.vm.playTrack(at: index)
        try await player.vm.settled()
        #expect(player.vm.selectedTrackIndex == index)
        #expect(starts(player) == [track(index)], "the engine started \(starts(player).map { name($0) })")
        #expect(player.vm.isPlaying)
    }

    @Test("an index past the queue changes nothing and starts nothing", arguments: [5, 99])
    func anIndexPastTheQueueIsIgnored(index: Int) async throws {
        let player = try await FakePlayer.launched(tracks: 5)
        player.vm.selectedTrackIndex = 0
        player.vm.playTrack(at: index)
        try await player.vm.settled()
        #expect(player.vm.selectedTrackIndex == 0)
        #expect(starts(player).isEmpty)
        #expect(player.vm.errorMessage == nil)
    }

    @Test("on an empty queue nothing is selected and nothing starts")
    func anEmptyQueueStartsNothing() async throws {
        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.playTrack(at: 0)
        try await player.vm.settled()
        #expect(player.vm.selectedTrackIndex == nil)
        #expect(starts(player).isEmpty)
    }

    @Test("a second playTrack replaces the first: both start, the newest stands and only it arms a next song")
    func aSecondPlayTrackReplacesTheFirst() async throws {
        let player = try await FakePlayer.launched(tracks: 5)
        player.vm.playTrack(at: 0)
        player.vm.playTrack(at: 3)
        try await player.vm.settled()
        #expect(player.vm.selectedTrackIndex == 3)
        // Both reach the engine (their hops keep no order between them); only the newest primes.
        #expect(starts(player).count == 2 && Set(starts(player)) == [track(0), track(3)])
        #expect(player.engine.state.withLock(\.nextTracks) == [track(4)], "the replaced start primed a next song")
        #expect(player.vm.isPlaying && player.vm.transportCommand == nil)
    }
}
