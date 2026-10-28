@testable import AdaptiveSound
import Foundation
import LibraryStore
import PlaybackQueueKit
import RigKit
import SQLite3
import Testing

// MARK: - The queue's record at its edges: a store that fails the read, a damaged record, a playhead alone (VM-QS)

//
// The shipped `AudioViewModel` over `FakeEngine`, its library a real `LibraryStore` (`QueueStateWorld`). A store
// read that fails — not a damaged record — is read once more, and when it fails again the writer stays closed,
// so this session's queue never overwrites one it never read (review N1). A write of the playhead alone builds
// no record (review S5), counted through the writer's book (`QueueStateBook.recordsBuilt`). A scrub while playing
// is the listener's choice of place, written at once like a pause — not left to the 5 s cadence (founder,
// 2026-10-28).

extension QueueStateWorld {
    /// Run `sql` on the library's file through a connection of the test's own — the store sees the change at
    /// its next statement. Here: a table hidden and brought back, so the store's read fails as a store error.
    func execute(_ sql: String) throws {
        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        let path = directory.appendingPathComponent("library.sqlite3").path
        try #require(sqlite3_open(path, &connection) == SQLITE_OK, "the library file did not open")
        let result = sqlite3_exec(connection, sql, nil, nil, nil)
        try #require(result == SQLITE_OK, "\(sql): \(String(cString: sqlite3_errmsg(connection)))")
    }
}

@MainActor
@Suite("The queue's record at its edges (VM-QS)", .timeLimit(.minutes(3)), .attachingLogTail)
struct QueueStateEdgeTests {
    /// The stored queue [t0, t1, t2], t1 selected, paused at 30 s — and what the store holds for it.
    private func storeThreeSongs(in world: QueueStateWorld) async throws -> StoredQueueState {
        let first = try await world.launch()
        first.vm.playNow((0 ..< 3).map(audioFile), startAt: 1)
        try await playing(first)
        try movePlayhead(first, to: 30)
        first.vm.pause()
        try await first.vm.settled()
        return try #require(try await world.stored(after: first))
    }

    @Test("VM-QS-13 (N1): a store that fails the restore's read twice — this session's queue is never written")
    func unreadableStoreKeepsTheWriterClosed() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let stored = try await storeThreeSongs(in: world)
        try world.execute("ALTER TABLE queue_state RENAME TO queue_state_hidden;") // every read fails

        let player = try await world.launch()
        #expect(player.vm.queue.isEmpty && !player.vm.queueStateBook.isOpen, "the writer opened on a failed read")
        // The store works again (the failure passed); the session plays on: a song started, its playhead past
        // the cadence, a pause — each asks for a write.
        try world.execute("ALTER TABLE queue_state_hidden RENAME TO queue_state;")
        let asked = player.vm.queueStateBook.revision
        player.vm.playNow([audioFile(2)], startAt: 0)
        try await playing(player)
        try movePlayhead(player, to: 12)
        player.vm.pause()
        try await player.vm.settled()
        await player.vm.queueStateWriter.flush()
        #expect(player.vm.queueStateBook.revision > asked, "the session changed nothing it could have written")
        #expect(player.vm.queueStateBook.recordsBuilt == 0, "the writer built a record to write")
        #expect(try await world.store.queueState() == stored, "the stored queue was overwritten")
    }

    @Test("VM-QS-14 (N1): a damaged record restores nothing; the session's queue is written whole")
    func damagedRecordRestoresEmpty() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        try await world.store.saveQueueState(record: #"{"format":1,"slots":[{"track":"#, offset: 30)

        let player = try await world.launch()
        #expect(player.vm.queue.isEmpty && player.vm.queueStateBook.isOpen, "a damaged record kept the writer closed")
        player.vm.playNow([audioFile(0), audioFile(2)], startAt: 1)
        try await playing(player)
        let stored = try #require(try await world.stored(after: player))
        let record = try QueueResumeRecord(storedQueue: stored.record, offset: stored.offset ?? 0)
        #expect(record.slots == [1, 3].map { .track(id: $0) } && record.cursor == 1, "the queue was not written whole")
    }

    @Test("VM-QS-15 (S5): a write of the playhead alone — the 5 s cadence, a pause, a scrub — builds no record")
    func playheadWritesBuildNoRecord() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let player = try await world.launch()
        player.vm.playNow((0 ..< 3).map(audioFile), startAt: 0)
        try await playing(player)
        let start = try #require(try await world.stored(after: player))
        let built = player.vm.queueStateBook.recordsBuilt
        for seconds in stride(from: 5.0, through: 30.0, by: 5.0) {
            try movePlayhead(player, to: seconds)
            #expect(try await world.stored(after: player)?.offset == seconds, "the playhead at \(seconds) s")
        }
        player.vm.pause()
        try await player.vm.settled()
        player.vm.duration = 200
        player.vm.seek(to: 90) // a scrub while paused
        let paused = try await world.stored(after: player)
        #expect(paused?.offset == 90 && paused?.revision == start.revision, "the scrub was not written alone")
        let rebuilt = player.vm.queueStateBook.recordsBuilt - built
        #expect(rebuilt == 0, "\(rebuilt) whole records built for writes of the playhead alone")
    }

    @Test("VM-QS-16: a scrub while playing is written at once, a small one back too; a relaunch comes back there")
    func scrubWhilePlayingIsKeptAtOnce() async throws {
        let world = try await QueueStateWorld(songs: 3)
        defer { world.discard() }
        let player = try await world.launch()
        player.vm.playNow((0 ..< 3).map(audioFile), startAt: 1)
        try await playing(player)
        player.vm.duration = 200
        try movePlayhead(player, to: 30) // the song's own progress, written at the cadence
        let start = try #require(try await world.stored(after: player))
        #expect(start.offset == 30)
        let built = player.vm.queueStateBook.recordsBuilt
        // Each scrub is under the cadence from the place last written: 3 s on, then 2 s back. No tick follows it.
        for target in [33.0, 31.0] {
            player.vm.seek(to: target)
            let stored = try await world.stored(after: player)
            #expect(stored?.offset == target && stored?.revision == start.revision && stored?.record == start.record,
                    "the scrub to \(target) s was not written at once, alone: stored @\(stored?.offset ?? -1)")
        }
        #expect(player.vm.queueStateBook.recordsBuilt == built, "a scrub's write built the whole record")

        // Killed right after the scrub, never quit: a relaunch has only what the writer wrote.
        let relaunched = try await world.launch()
        #expect(relaunched.vm.selectedTrackIndex == 1, "the relaunch selected another song")
        #expect(relaunched.vm.pausedResumePosition == 31 && relaunched.vm.playbackPosition == 31,
                "the relaunch is at \(relaunched.vm.playbackPosition) s, not where the listener scrubbed to")
    }
}
