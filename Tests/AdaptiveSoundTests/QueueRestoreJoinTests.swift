@testable import AdaptiveSound
import Foundation
import LibraryStore
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - The restore meets what the user did before it, and the library's moves (R1.1-B; lane 5's seams) (VM-QS)

//
// Files opened at launch (Open With, a drop on the Dock icon, Open…) can reach the queue before the stored
// queue is restored: they join it right after the restored song, as they would had the restore come first —
// the two orders end in the same queue (VM-QS-08). Lane 5's verbs are `playTrackNextNow` + `playNext`; these
// tests call the same. A song "Use this drive" re-roots to a new path is followed by the live queue, its armed
// next song armed again at the new path (VM-QS-10). Shared world and helpers: `QueueRestoreTests.swift`.

@MainActor
@Suite("The restore joins what came first, and the queue follows the library (VM-QS)", .timeLimit(.minutes(3)),
       .attachingLogTail)
struct QueueRestoreJoinTests {
    /// The stored queue [t0, t1, t2, t3], t1 selected, paused at 30 s.
    private func storeFourSongs(in world: QueueStateWorld, shuffle: Bool = false) async throws -> FakePlayer {
        let first = try await world.launch(shuffle: shuffle)
        first.vm.playNow((0 ..< 4).map(audioFile), startAt: 1)
        try await playing(first)
        try movePlayhead(first, to: 30)
        first.vm.pause()
        try await first.vm.settled()
        _ = try await world.stored(after: first)
        return first
    }

    /// Open `files` as lane 5's Open…, drop and Open With do: the first plays now, right after the song
    /// selected; the rest after it (`playTrackNextNow` + `playNext`).
    private func open(_ files: [AudioFile], in player: FakePlayer) async throws {
        player.vm.playTrackNextNow(files[0])
        _ = player.vm.playNext(Array(files.dropFirst()))
        try await playing(player)
    }

    @Test("VM-QS-08: files opened at launch, before the restore, join the restored queue after its song")
    func filesOpenedAtLaunchJoinTheRestoredQueue() async throws {
        let opened = ["Opened A", "Opened B"]
        // The restore first, then the files (what happens when the store is ready before they open).
        let first = try await QueueStateWorld(songs: 4)
        defer { first.discard() }
        _ = try await storeFourSongs(in: first)
        let restoredFirst = try await first.launch()
        try await open(opened.map { first.looseFile($0) }, in: restoredFirst)
        // The files first — Open With launching the app — then the restore.
        let second = try await QueueStateWorld(songs: 4)
        defer { second.discard() }
        _ = try await storeFourSongs(in: second)
        let openedFirst = try await FakePlayer.launched(tracks: 0)
        try await open(opened.map { second.looseFile($0) }, in: openedFirst)
        second.attach(openedFirst.vm)
        openedFirst.vm.hydrateQueueOnLaunch()
        try await openedFirst.vm.settled()

        let names = { (player: FakePlayer) in player.vm.queue.map(\.file.name) }
        #expect(names(openedFirst) == ["t0", "t1", "Opened A", "Opened B", "t2", "t3"])
        #expect(names(openedFirst) == names(restoredFirst), "the two orders ended in different queues")
        for player in [openedFirst, restoredFirst] {
            #expect(player.vm.selectedTrackIndex == 2 && player.vm.isPlaying, "the opened file is not playing")
            #expect(player.vm.pendingNextIndex == 3, "the second opened file is not next")
        }
        let stored = try #require(try await second.stored(after: openedFirst))
        let record = try QueueResumeRecord(storedQueue: stored.record, offset: 0)
        #expect(record.slots.count == 6 && record.cursor == 2, "the joined queue was not written")
    }

    @Test("VM-QS-09: under shuffle, files opened before the restore play now; the restored pass goes on after them")
    func fileOpenedBeforeTheRestoreUnderShuffle() async throws {
        let world = try await QueueStateWorld(songs: 4)
        defer { world.discard() }
        let first = try await storeFourSongs(in: world, shuffle: true)
        let kept = try #require(passRefs(first.vm))

        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.shuffleEnabled = true
        let files = [world.looseFile("Opened A"), world.looseFile("Opened B")]
        try await open(files, in: player)
        world.attach(player.vm)
        player.vm.hydrateQueueOnLaunch()
        try await player.vm.settled()
        var pass = try #require(passRefs(player.vm))
        let opened = files.map(\.queueSlotRef)
        #expect(pass.current == opened[0], "the opened file is not the pass's song")
        #expect(pass.previous(repeatMode: 0) == kept.current, "the restored song is not the one before it")
        #expect(pass.peekNext(repeatMode: 0) == opened[1], "the second opened file is not next")
        pass.arrive(at: opened[1])
        #expect(pass.peekNext(repeatMode: 0) == kept.peekNext(repeatMode: 0), "the restored pass does not go on")
        #expect(pass.permutation.filter { !opened.contains($0) } == kept.permutation)
    }

    @Test("VM-QS-10: a queued song \"Use this drive\" moves plays from its new path; armed, it is armed there")
    func movedSongsAreFollowed() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let player = try await world.launch()
        player.vm.playNow((0 ..< 3).map(audioFile), startAt: 0)
        try await playing(player)
        #expect(player.engine.state.withLock(\.nextTracks).last == track(1))
        let slot = player.vm.queue[1].id
        // The store re-roots song 2 (t1) to another drive, and the library says its content changed.
        let moved = URL(fileURLWithPath: "/Volumes/T7 1/ondeck/t1.flac")
        try await world.store.moveTrack(id: 2, newURL: moved, newFolderID: nil, newRelativePath: "t1.flac")
        try #require(player.vm.library).libraryRevision &+= 1
        try await until("the queue to play the moved song from its new path") {
            player.vm.queue[1].file.absoluteURL == moved
        }
        #expect(player.vm.queue[1].id == slot && player.vm.queue[1].file.trackID == 2, "the slot was replaced")
        try await player.vm.settled()
        #expect(player.engine.state.withLock(\.nextTracks).last == moved, "the armed song was not armed again")
        #expect(player.vm.queue.map(\.file.absoluteURL) == [track(0), moved, track(2)])
    }

    @Test("VM-QS-11 (known issue, +Playback): an open during its start, joined by the restore, primes the old row")
    func joinDuringTheOpenedFilesStart() async throws {
        let world = try await QueueStateWorld(songs: 4)
        defer { world.discard() }
        _ = try await storeFourSongs(in: world)
        let rig = Rig(tracks: 0)
        rig.engine.holdTransport(true)
        rig.vm.playTrackNextNow(world.looseFile("Opened")) // its start held at the engine
        try await rig.runViewModelOut()
        world.attach(rig.vm)
        rig.vm.hydrateQueueOnLaunch()
        try await until("the restore to join the queue") { rig.vm.queue.count == 5 }
        rig.engine.holdTransport(false)
        try await rig.quiesce()
        #expect(rig.vm.queue.map(\.file.name) == ["t0", "t1", "Opened", "t2", "t3"] && rig.vm.selectedTrackIndex == 2)
        // `startPlayback` keeps the start's ROW (`startIndex`, AudioViewModel+Playback.swift — not this lane's) and
        // its prime arms the row after it: t1, not t2. The fix: keep the slot (`selectedSlotID`) and find its row at
        // the prime. When it lands, this known issue stops being recorded and the test fails: drop the wrapper.
        withKnownIssue("the prime arms the row after the start's old row (+Playback's startIndex)") {
            #expect(rig.vm.pendingNextIndex == 3, "\(rig.state)")
        }
    }
}
