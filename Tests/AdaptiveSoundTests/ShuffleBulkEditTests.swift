@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Big edits under shuffle stay linear on the main actor (R1.1-B, review S3) (VM-SB)

//
// The shipped `AudioViewModel` over `FakeEngine` (`FakePlayer`). Every queue edit reaches the shuffle pass in
// the queue's didSet, on the main actor; done one song at a time, a 20,000-song edit shifts the pass's line
// once per song — about 10⁸ slot moves, seconds in a debug build. These count what the pass moved
// (`ShufflePassTally`, rule 2: the component's own count, never a clock): each edit writes the pass's line at
// most once. The pass's own rule is `ShufflePassTests` (VM-SP-16, VM-SP-17).

/// 20,000 files outside the library, by number: a queue of them is kept, and comes back, by their paths.
private func manySongs(from first: Int = 100) -> [AudioFile] {
    (first ..< first + 20000).map { AudioFile(looseFileAt: URL(fileURLWithPath: "/nonexistent/many/s\($0).flac")) }
}

@MainActor
@Suite("Big edits under shuffle stay linear (VM-SB)", .timeLimit(.minutes(3)), .attachingLogTail)
struct ShuffleBulkEditTests {
    @Test("VM-SB-01: a 20,000-song Add to Queue, then Play Next, under shuffle while an album plays")
    func addAndPlayNextUnderShuffle() async throws {
        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.shuffleEnabled = true
        player.vm.playNow((0 ..< 12).map(audioFile), startAt: 3)
        try await playing(player)

        let added = ShufflePassTally()
        let songs = manySongs()
        ShufflePassTally.$current.withValue(added) { _ = player.vm.appendToQueue(songs) }
        let queued = player.vm.queue.count
        #expect(added.slotsMoved <= queued, "an Add to Queue moved \(added.slotsMoved) slots for \(queued) songs")
        #expect(player.vm.shufflePass?.permutation.count == queued && player.vm.shufflePass?.position == 0)

        let playedNext = ShufflePassTally()
        let next = manySongs(from: 30000)
        ShufflePassTally.$current.withValue(playedNext) { _ = player.vm.playNext(next) }
        let total = player.vm.queue.count
        #expect(playedNext.slotsMoved <= total, "a Play Next moved \(playedNext.slotsMoved) slots for \(total) songs")
        let pass = try #require(player.vm.shufflePass)
        #expect(pass.peekNext(repeatMode: 0) == player.vm.queue[4].id, "the first song played next is not next")
        try await player.vm.settled()
    }

    @Test("VM-SB-02: a 20,000-song queue restored under shuffle, joined by a file opened before it")
    func launchJoinUnderShuffle() async throws {
        let world = try await QueueStateWorld(songs: 0)
        defer { world.discard() }
        let earlier = try await world.launch(shuffle: true)
        earlier.vm.playNow(manySongs(), startAt: 5000)
        try await playing(earlier)
        _ = try await world.stored(after: earlier)

        // Open With at launch, before the store is ready: a pass over the one opened song exists.
        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.shuffleEnabled = true
        player.vm.playTrackNextNow(world.looseFile("Opened"))
        try await playing(player)
        world.attach(player.vm)
        let joined = ShufflePassTally()
        try await ShufflePassTally.$current.withValue(joined) {
            player.vm.hydrateQueueOnLaunch()
            try await player.vm.settled()
        }
        let queued = player.vm.queue.count
        try #require(queued == 20001, "the restore did not join: \(queued) songs")
        // One splice of the restored pass. The pass over the opened song alone used to follow every restored slot
        // first — one insert per song — and was then thrown away.
        #expect(joined.slotsMoved <= queued, "the join moved \(joined.slotsMoved) slots for \(queued) songs")
        #expect(player.vm.shufflePass?.current == player.vm.selectedSlotID && player.vm.isPlaying)
    }
}
