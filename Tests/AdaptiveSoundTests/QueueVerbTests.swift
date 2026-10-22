@testable import AdaptiveSound
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Play Now / Play Next / Add to Queue on the real view model (S9-Q2, VM-Q)

//
// The shipped `AudioViewModel` against `OnDeckEngineModel` (`Rig`): each verb edits the queue and keeps the
// engine's on-deck pick right — armed only while a song plays, re-armed only when the next song changed.
// These were the mirror's queue-op cases (`MockAdvanceController`, retired). The mirror still deduplicated
// what was added (the S9 contract); the app has not since S10.2 — the same song may be queued twice, as
// a slot of its own — so the count a verb returns is the slots it added (`theVerbsReturnTheSlotsAdded`).

@MainActor
@Suite("Queue verbs on the real view model (VM-Q)", .timeLimit(.minutes(3)), .attachingLogTail)
struct QueueVerbTests {
    /// Let what a verb sent the engine land.
    private func land(_ rig: Rig) async throws {
        try await rig.settle()
        rig.engine.drain()
    }

    private func names(_ rig: Rig) -> [String] {
        rig.vm.queue.map { name($0.file.absoluteURL) }
    }

    @Test("VM-Q-01: Play Now replaces the queue, plays from the song asked for, and arms the one after it")
    func playNowReplacesTheQueueAndPlays() async throws {
        let rig = Rig(tracks: 1)
        rig.vm.playNow([audioFile(5), audioFile(6), audioFile(7)], startAt: 1)
        try await land(rig)
        try await rig.waitUntil("the start to play") { rig.vm.isPlaying }
        #expect(names(rig) == ["t5", "t6", "t7"], "the old queue is gone")
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.vm.pendingNextIndex == 2)
        #expect(rig.engine.current == track(6) && rig.engine.armed == track(7), "\(rig.state)")
    }

    @Test("VM-Q-02: Add to Queue mid-queue leaves the armed song alone — no request")
    func anAppendMidQueueLeavesTheDeck() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        let requests = rig.vm.onDeckSequence
        rig.vm.appendToQueue([audioFile(9)])
        #expect(rig.vm.queue.count == 4)
        #expect(rig.vm.pendingNextIndex == 1)
        #expect(rig.vm.onDeckSequence == requests, "an append that changes no next song re-armed the engine")
        #expect(rig.engine.armed == track(1))
    }

    @Test("VM-Q-03: Add to Queue on the last song arms the first song added, and it plays next")
    func anAppendAtTheEndArmsTheFirstAddedSong() async throws {
        let rig = try await Rig.playing(tracks: 2, pure: false)
        try await rig.endTrackAndFollow()
        #expect(rig.vm.selectedTrackIndex == 1)
        #expect(rig.vm.pendingNextIndex == nil)
        rig.vm.appendToQueue([audioFile(8), audioFile(9)])
        #expect(rig.vm.pendingNextIndex == 2)
        try await land(rig)
        #expect(rig.engine.armed == track(8))
        try await rig.endTrackAndFollow()
        #expect(rig.engine.current == track(8) && rig.shown == track(8), "\(rig.state)")
    }

    @Test("VM-Q-04: Add to Queue under shuffle keeps the shuffle pick — no re-roll, no request")
    func anAppendUnderShuffleKeepsThePick() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false, shuffle: true)
        let pick = rig.vm.pendingNextIndex
        let requests = rig.vm.onDeckSequence
        rig.vm.appendToQueue([audioFile(9)])
        #expect(rig.vm.queue.count == 4)
        #expect(rig.vm.pendingNextIndex == pick)
        #expect(rig.vm.onDeckSequence == requests, "the shuffle pick was re-rolled")
    }

    @Test("VM-Q-05: Add to Queue while stopped only queues: nothing is armed, nothing plays")
    func anAppendWhileStoppedOnlyQueues() {
        let rig = Rig(tracks: 2)
        rig.vm.selectedTrackIndex = 0
        rig.vm.appendToQueue([audioFile(9)])
        #expect(rig.vm.queue.count == 3)
        #expect(!rig.vm.isPlaying)
        #expect(rig.vm.pendingNextIndex == nil)
        #expect(rig.vm.onDeckSequence == 0 && rig.vm.transportEpoch == 0, "the engine was sent something")
    }

    @Test("VM-Q-06: Play Next inserts after the playing song and arms it")
    func playNextInsertsAfterTheSongAndArmsIt() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        rig.vm.playNext([audioFile(9)])
        #expect(names(rig) == ["t0", "t9", "t1", "t2"])
        #expect(rig.vm.pendingNextIndex == 1)
        try await land(rig)
        #expect(rig.engine.armed == track(9))
        try await rig.endTrackAndFollow()
        #expect(rig.engine.current == track(9) && rig.shown == track(9), "\(rig.state)")
    }

    @Test("VM-Q-07: Play Next under shuffle still plays the inserted song next")
    func playNextBeatsShuffle() async throws {
        let rig = try await Rig.playing(tracks: 5, at: 2, pure: false, shuffle: true)
        rig.vm.playNext([audioFile(9)])
        #expect(rig.vm.queue[3].file.absoluteURL == track(9))
        #expect(rig.vm.pendingNextIndex == 3, "Play Next is honoured under shuffle")
        try await land(rig)
        #expect(rig.engine.armed == track(9), "\(rig.state)")
    }

    @Test("VM-Q-08: Play Next with nothing selected adds to the end")
    func playNextWithNothingSelectedAppends() {
        let rig = Rig(tracks: 2)
        rig.vm.playNext([audioFile(9)])
        #expect(names(rig) == ["t0", "t1", "t9"])
        #expect(rig.vm.pendingNextIndex == nil)
        #expect(rig.vm.onDeckSequence == 0 && rig.vm.transportEpoch == 0, "the engine was sent something")
    }

    @Test("VM-Q-09: Play Next while paused inserts after the paused song, unarmed — Play re-arms")
    func playNextWhilePausedInsertsUnarmed() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        rig.vm.pause()
        try await rig.quiesce()
        let requests = rig.vm.onDeckSequence
        rig.vm.playNext([audioFile(9)])
        #expect(names(rig) == ["t0", "t9", "t1", "t2"], "paused, Play Next goes after the paused song")
        #expect(rig.vm.pendingNextIndex == nil)
        #expect(rig.vm.onDeckSequence == requests, "a paused Play Next armed the stopped engine")
    }

    @Test("VM-Q-10: Play Next on the last song inserts at the end and arms it")
    func playNextOnTheLastSongArmsIt() async throws {
        let rig = try await Rig.playing(tracks: 2, pure: false)
        try await rig.endTrackAndFollow()
        rig.vm.playNext([audioFile(9)])
        #expect(names(rig) == ["t0", "t1", "t9"])
        #expect(rig.vm.pendingNextIndex == 2)
        try await land(rig)
        #expect(rig.engine.armed == track(9), "\(rig.state)")
    }

    @Test("VM-Q-12: nothing to add changes nothing, for all three verbs")
    func emptyInputChangesNothing() async throws {
        let rig = try await Rig.playing(tracks: 2, pure: false)
        let slots = rig.vm.queue.map(\.id)
        let requests = rig.vm.onDeckSequence
        let commands = rig.vm.transportEpoch
        rig.vm.playNow([])
        #expect(rig.vm.playNext([]) == 0)
        #expect(rig.vm.appendToQueue([]) == 0)
        #expect(rig.vm.queue.map(\.id) == slots)
        #expect(rig.vm.onDeckSequence == requests && rig.vm.transportEpoch == commands, "the engine was sent something")
    }

    @Test("VM-Q-11/13/14/15 (S10.2): a song already queued is queued again, and a verb returns the slots it added")
    func theVerbsReturnTheSlotsAdded() async throws {
        let rig = try await Rig.playing(tracks: 3, pure: false)
        #expect(rig.vm.appendToQueue([audioFile(1), audioFile(9), audioFile(9)]) == 3)
        #expect(rig.vm.playNext([audioFile(0)]) == 1)
        #expect(names(rig) == ["t0", "t0", "t1", "t2", "t1", "t9", "t9"])
        #expect(Set(rig.vm.queue.map(\.id)).count == 7, "each added song is a slot of its own")
    }
}
