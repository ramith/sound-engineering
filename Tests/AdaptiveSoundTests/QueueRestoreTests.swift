@testable import AdaptiveSound
import Foundation
import LibraryStore
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - The queue's resume record on the real view model and a real store (R1.1-B; C-65, KI-PB-21) (VM-QS)

//
// The shipped `AudioViewModel` over `FakeEngine` (`FakePlayer`), its library a real `LibraryStore` in a
// folder of its own: a view model writes its queue through its one writer; a second one, launched over the
// same store, restores it. The record's own rules are `QueueResumeRecordTests` (PlaybackQueueKit), the
// store's transaction `ChecksQueueState` (VerifyLibraryStore), and a kill -9 at random points
// `QueueStateKillTests`. Every wait is for a state: the writer's `flush()` is the witness that every write
// asked for has landed.

/// A library store of its own, holding `songs` library songs — ids 1…songs, as `audioFile(_:)` names them —
/// and the view models launched over it.
@MainActor
final class QueueStateWorld {
    let directory: URL
    let store: LibraryStore
    /// The library models the view models reach their store through (theirs is a weak reference).
    private var libraries: [LibraryModel] = []

    init(songs: Int) async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try await LibraryStore(url: directory.appendingPathComponent("library.sqlite3"), appBuild: "test")
        let files = (0 ..< songs).map {
            ScannedFile(url: track($0), name: "t\($0)", format: "FLAC", fileSize: 1, mtime: 1)
        }
        let ids = try await store.upsert(files, folderID: nil, generation: store.beginScanGeneration())
        #expect(ids == (0 ..< songs).map { Int64($0 + 1) }, "the songs are not ids 1…\(songs)")
    }

    /// A view model launched over the store as the app launches one — the engine up, then the store ready —
    /// with `shuffle` as the listener's setting, its queue restored from what is stored.
    func launch(shuffle: Bool = false) async throws -> FakePlayer {
        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.shuffleEnabled = shuffle
        attach(player.vm)
        player.vm.hydrateQueueOnLaunch()
        try await player.vm.settled()
        return player
    }

    /// Give `viewModel` the store, as `LibraryModel.onStoreReady` would, without the restore.
    func attach(_ viewModel: AudioViewModel) {
        let library = LibraryModel(storeless: ())
        library.store = store
        libraries.append(library)
        viewModel.library = library
    }

    /// What is stored now, once everything `player` asked its writer for has landed.
    func stored(after player: FakePlayer) async throws -> StoredQueueState? {
        await player.vm.queueStateWriter.flush()
        return try await store.queueState()
    }

    func discard() {
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - What the queue-state suites share

extension QueueStateWorld {
    /// A file outside the library, in this world's folder: no `tracks` row, ever.
    func looseFile(_ name: String) -> AudioFile {
        let url = directory.appendingPathComponent("\(name).flac")
        return AudioFile(name: name, relativePath: "", absoluteURL: url, format: "FLAC", durationSeconds: 0)
    }
}

/// The song `player`'s view model started plays: its start and its on-deck request landed.
@MainActor
func playing(_ player: FakePlayer) async throws {
    try await player.vm.settled()
    try await until("the song to play") { player.vm.isPlaying && player.vm.transportCommand == nil }
}

/// The engine's playhead at `seconds`, and the tick that reads it.
@MainActor
func movePlayhead(_ player: FakePlayer, to seconds: Double) throws {
    player.engineReports(position: seconds)
    try player.tick()
}

/// The pass over the queue's slots, as what each slot plays: comparable across two view models.
@MainActor
func passRefs(_ vm: AudioViewModel) -> ShufflePass<QueueSlotRef>? {
    vm.shufflePass?.relabeled { id in vm.queue.first { $0.id == id }?.file.queueSlotRef }
}

@MainActor
@Suite("The queue's resume record on the real view model (VM-QS)", .timeLimit(.minutes(3)), .attachingLogTail)
struct QueueRestoreTests {
    @Test("VM-QS-01 (§6 shuffle 8): the queue, the song, its place and the shuffle pass come back after a relaunch")
    func everythingComesBack() async throws {
        let world = try await QueueStateWorld(songs: 12)
        defer { world.discard() }
        let first = try await world.launch(shuffle: true)
        first.vm.playNow((0 ..< 12).map(audioFile), startAt: 4)
        try await first.vm.settled()
        for seam in 1 ... 3 { // three songs on into the pass
            first.engineReports(position: 0, transitionCount: UInt64(seam))
            try first.tick()
            try await first.vm.settled()
        }
        try movePlayhead(first, to: 42)
        first.vm.pause()
        try await first.vm.settled()
        let stored = try await world.stored(after: first)
        #expect(stored?.offset == 42)

        let second = try await world.launch(shuffle: true)
        #expect(second.vm.queue.map(\.file.queueSlotRef) == first.vm.queue.map(\.file.queueSlotRef))
        #expect(second.vm.selectedSlotID.flatMap(second.vm.queueRow) == first.vm.selectedTrackIndex)
        #expect(second.vm.pausedResumePosition == 42 && second.vm.playbackPosition == 42 && !second.vm.isPlaying)
        let pass = try #require(passRefs(second.vm))
        #expect(pass == passRefs(first.vm), "the permutation, the place or the history changed")
        #expect(pass.position == 3 && pass.seed == first.vm.shufflePass?.seed)
    }

    @Test("VM-QS-02 (S5): a loose file in the queue comes back by its path, and no tracks row is made")
    func looseFileComesBack() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let first = try await world.launch()
        let loose = world.looseFile("Field Recording")
        first.vm.playNow([audioFile(0), loose, audioFile(2)], startAt: 1)
        try await first.vm.settled()
        try movePlayhead(first, to: 7)
        first.vm.pause()
        try await first.vm.settled()
        _ = try await world.stored(after: first)

        let second = try await world.launch()
        #expect(second.vm.queue.map(\.file.absoluteURL) == [track(0), loose.absoluteURL, track(2)])
        #expect(second.vm.selectedTrackIndex == 1 && second.vm.pausedResumePosition == 7)
        #expect(second.vm.queue[1].file.trackID == nil && second.vm.queue[1].file.name == "Field Recording")
        #expect(try await world.store.trackCount() == 3, "a tracks row was made for the loose file")
    }

    @Test("VM-QS-03 (the cadence): the playhead is written every 5 s of the song, at once at a pause, alone")
    func playheadCadence() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let player = try await world.launch()
        player.vm.playNow((0 ..< 3).map(audioFile), startAt: 0)
        try await playing(player)
        let start = try #require(try await world.stored(after: player))
        try movePlayhead(player, to: 4.9) // under the cadence: no write asked for
        #expect(try await world.stored(after: player) == start)
        try movePlayhead(player, to: 5.0)
        let moved = StoredQueueState(revision: start.revision, record: start.record, offset: 5.0)
        #expect(try await world.stored(after: player) == moved, "a playhead move rewrote the queue, or was not written")
        try movePlayhead(player, to: 9.5)
        #expect(try await world.stored(after: player)?.offset == 5.0, "written before the next 5 s")
        player.vm.pause()
        try await player.vm.settled()
        let paused = try await world.stored(after: player)
        #expect(paused?.offset == 9.5 && paused?.revision == start.revision, "a pause is written at once, alone")
    }

    @Test("VM-QS-04: a queue built before the restore joins the stored one after its song, and is written")
    func aQueueBuiltBeforeTheRestoreJoins() async throws {
        let world = try await QueueStateWorld(songs: 4)
        defer { world.discard() }
        let earlier = try await world.launch()
        earlier.vm.playNow([audioFile(0), audioFile(1)], startAt: 0)
        try await earlier.vm.settled()
        _ = try await world.stored(after: earlier)

        let player = try await FakePlayer.launched(tracks: 0)
        player.vm.playNow([audioFile(3)], startAt: 0) // before the store is ready
        try await playing(player)
        world.attach(player.vm)
        player.vm.hydrateQueueOnLaunch()
        try await player.vm.settled()
        #expect(player.vm.queue.map(\.file.absoluteURL) == [track(0), track(3), track(1)],
                "the stored queue or the user's was lost")
        #expect(player.vm.selectedTrackIndex == 1 && player.vm.isPlaying, "the song the user started stopped")
        let stored = try #require(try await world.stored(after: player))
        let record = try QueueResumeRecord(storedQueue: stored.record, offset: 0)
        #expect(record.slots == [1, 4, 2].map { .track(id: $0) } && record.cursor == 1,
                "the joined queue was not written")
    }

    @Test("VM-QS-05: a library from before the record — the queue and its cursor come back once, then the keys go")
    func legacyQueueComesBackOnce() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        try await world.store.replaceEntries(playlistID: world.store.currentPlaylistID(), trackIDs: [3, 1, 2])
        let player = try await FakePlayer.launched(tracks: 0)
        let defaults = player.vm.defaults
        defaults.set(1, forKey: "queue.cursor.position")
        defaults.set(1, forKey: "queue.cursor.positionTrackID")
        defaults.set(33.0, forKey: "queue.cursor.offset")
        world.attach(player.vm)
        player.vm.hydrateQueueOnLaunch()
        try await player.vm.settled()
        #expect(player.vm.queue.map(\.file.absoluteURL) == [track(2), track(0), track(1)])
        #expect(player.vm.selectedTrackIndex == 1 && player.vm.pausedResumePosition == 33)
        let stored = try #require(try await world.stored(after: player))
        #expect(try QueueResumeRecord(storedQueue: stored.record, offset: 0).slots == [3, 1, 2].map { .track(id: $0) })
        #expect(stored.offset == 33)
        #expect(defaults.object(forKey: "queue.cursor.position") == nil, "the old cursor keys are kept")
        #expect(defaults.object(forKey: "queue.cursor.offset") == nil)
    }

    @Test("VM-QS-06: nothing is written before the restore read the store, nor after the quit's last write")
    func writesOnlyBetweenTheRestoreAndTheQuit() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let first = try await world.launch()
        first.vm.playNow((0 ..< 3).map(audioFile), startAt: 2)
        try await playing(first)
        try movePlayhead(first, to: 61)
        // The quit, as `+Lifecycle.shutdown` runs it: the playhead, the last write, then the stop.
        first.vm.persistQueueCursor()
        await first.vm.mirrorQueueNow()
        let atQuit = try #require(try await world.store.queueState())
        #expect(atQuit.offset == 61)
        first.vm.stopPlayback()
        try await first.vm.settled()
        #expect(first.vm.playbackPosition == 0)
        #expect(try await world.stored(after: first) == atQuit, "the stop after the quit's last write was written")

        // A view model whose store is ready but whose restore has not run: a queue built writes nothing.
        let second = try await FakePlayer.launched(tracks: 0)
        world.attach(second.vm)
        second.vm.shuffleEnabled = true
        second.vm.playNow([audioFile(1)], startAt: 0)
        try await playing(second)
        #expect(try await world.stored(after: second) == atQuit)
    }

    @Test("VM-QS-07: a song deleted while the app was closed drops out; the selected one gone starts at the top")
    func deletedSongsDropOut() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let first = try await world.launch()
        first.vm.playNow((0 ..< 3).map(audioFile), startAt: 1)
        try await first.vm.settled()
        try movePlayhead(first, to: 50)
        first.vm.pause()
        try await first.vm.settled()
        _ = try await world.stored(after: first)
        try await world.store.delete(id: 2) // t1, the selected song

        let second = try await world.launch()
        #expect(second.vm.queue.map(\.file.absoluteURL) == [track(0), track(2)])
        #expect(second.vm.selectedTrackIndex == nil && second.vm.playbackPosition == 0,
                "another song was selected at the gone song's place")
    }
}
