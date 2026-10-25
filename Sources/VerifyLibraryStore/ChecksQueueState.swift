// ChecksQueueState — R1.1-B, council C-65 / KI-PB-21: the v10 queue resume state.
//   QS-1 a v9 (previous-release) store holding a queue in the "current" playlist, a user playlist and
//        play history opens through the real open path: it reaches v10 with no queue record yet (the app
//        carries the old queue over once), and every user row — the old queue's entries too — kept.
//   QS-2 the migration is additive: every v9 table and index is in the v10 schema unchanged, the only new
//        objects are the two queue tables, and a v9 store upgraded converges on a fresh v10 install.
//   QS-3 the record and its playhead round-trip byte for byte, each new record takes the next revision, a
//        playhead write lands only on its own revision (a stale one writes nothing), and a reopened store
//        reads the same state.
//   QS-4 a half write is impossible: a write that fails after the record was replaced — the playhead
//        refused by its CHECK inside the same transaction — leaves the previous record and playhead whole.
//   QS-5 no reader ever sees a mix: readers racing a writer that alternates whole writes and playhead
//        writes always read a record with the playhead of its own revision.
// The process-level proof — SIGKILL at random points while the app's one writer writes, 100 kills —
// is `QueueStateKillTests` in AdaptiveSoundTests (`make stress`).

import Foundation
import GRDB
import LibraryStore

// MARK: - Registration

func queueStateCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "qs1-v10-queue-state-upgrade", run: checkQueueStateUpgrade),
        CheckCase(label: "qs2-v10-additive-convergence") { number, _ in checkQueueStateAdditive(number: number) },
        CheckCase(label: "qs3-queue-state-round-trip", run: checkQueueStateRoundTrip),
        CheckCase(label: "qs4-queue-state-no-half-write", run: checkQueueStateNoHalfWrite),
        CheckCase(label: "qs5-queue-state-no-mixed-read", run: checkQueueStateNoMixedRead),
    ]
}

// MARK: - QS-1 — the v9 → v10 upgrade

/// A v9 store at `url`: three songs, the queue [2, 3, 1] in the "current" playlist, a user playlist of
/// [1, 3], the first song played 4 times and loved.
private func seedV9Store(at url: URL) throws {
    let queue = try DatabaseQueue(path: url.path)
    try migrator(through: 9).migrate(queue)
    try queue.write { db in
        for index in 1 ... 3 {
            try db.execute(sql: """
            INSERT INTO tracks(id, url, relative_path, name, format, file_size, mtime, date_added, last_seen_scan,
                               play_count, loved)
            VALUES (?, ?, '', ?, 'FLAC', 8, 1, 1, 1, ?, ?);
            """, arguments: [index, "/qs1/\(index).flac", "song \(index)", index == 1 ? 4 : 0, index == 1])
        }
        let current = try Int64.fetchOne(db, sql: "SELECT id FROM playlists WHERE is_builtin = 1;")
        try db.execute(sql: "INSERT INTO playlists(name, is_builtin, created_at) VALUES ('Kept', 0, 1);")
        let kept = db.lastInsertedRowID
        let entries: [(Int64?, [Int64])] = [(current, [2, 3, 1]), (kept, [1, 3])]
        for (playlist, tracks) in entries {
            for (position, track) in tracks.enumerated() {
                try db.execute(
                    sql: "INSERT INTO playlist_entries(playlist_id, track_id, position, added_at) VALUES (?, ?, ?, 1);",
                    arguments: [playlist, track, position]
                )
            }
        }
    }
}

func checkQueueStateUpgrade(number: Int, url: URL) async -> Bool {
    do {
        try seedV9Store(at: url)
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard await store.schemaVersion() == currentSchemaVersion, try await store.queueState() == nil else {
            printFail(number, "QS-1: the upgraded store is not at v\(currentSchemaVersion), or holds a queue "
                + "record nobody wrote")
            return false
        }
        let queue = try await store.entries(inPlaylist: store.currentPlaylistID()).map(\.trackID)
        let kept = try await store.playlists().first { $0.name == "Kept" }
        let played = try await store.userState(trackID: 1)
        guard queue == [2, 3, 1], let kept, try await store.entries(inPlaylist: kept.id).map(\.trackID) == [1, 3],
              played?.playCount == 4, played?.loved == true else {
            printFail(number, "QS-1: the upgrade lost user data (the old queue, a playlist, or play history)")
            return false
        }
        printPass(number, "QS-1 the v9 → v10 upgrade: a v9 store with a queue in “current”, a playlist and play "
            + "history reaches v\(currentSchemaVersion) with no queue record yet and every user row kept")
        return true
    } catch {
        printFail(number, "QS-1 threw: \(error)"); return false
    }
}

// MARK: - QS-2 — additive, and converging

func checkQueueStateAdditive(number: Int) -> Bool {
    do {
        let previous = try DatabaseQueue()
        try migrator(through: 9).migrate(previous)
        let before = try Set(previous.read { db in try schemaFingerprint(db) }.split(separator: "\n"))
        try migrator(through: 10).migrate(previous)
        let after = try Set(previous.read { db in try schemaFingerprint(db) }.split(separator: "\n"))
        let added = after.subtracting(before).map { $0.split(separator: "|")[1] }.sorted()
        guard before.isSubset(of: after), added == ["queue_playhead", "queue_state"] else {
            printFail(number, "QS-2: v10 is not additive — v9 objects changed or went "
                + "(\(before.subtracting(after).sorted())), or it added more than its two tables (\(added))")
            return false
        }
        let fresh = try DatabaseQueue()
        try migrator(through: 10).migrate(fresh)
        guard try fresh.read({ db in try schemaFingerprint(db) }) == previous.read({ db in try schemaFingerprint(db) }) else {
            printFail(number, "QS-2: a v9 store upgraded to v10 differs from a fresh v10 install")
            return false
        }
        printPass(number, "QS-2 v10 is additive: every v9 table and index unchanged, only queue_state and "
            + "queue_playhead added, and an upgraded v9 store converges on a fresh install")
        return true
    } catch {
        printFail(number, "QS-2 threw: \(error)"); return false
    }
}

// MARK: - QS-3 — round trip, revisions, the playhead's own revision, a reopen

func checkQueueStateRoundTrip(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // Text the store must keep byte for byte: an escaped path, a name stored decomposed (NFD, which
        // Swift's `==` would call equal to its composed spelling), a Sinhala conjunct with its joiner.
        let first = #"{"format":1,"slots":[{"loose":{"path":"\/Volumes\/T7\/"#
            + "Cafe\u{301} — ශ්\u{200D}රී.flac" + #""}}]}"#
        let second = #"{"format":1,"slots":[{"track":{"id":7}}],"cursor":0}"#
        let one = try await store.saveQueueState(record: first, offset: 12.5)
        let read = try await store.queueState()
        guard one == 1, read?.revision == 1, read?.offset == 12.5,
              read.map({ Array($0.record.utf8) }) == Array(first.utf8),
              try await store.saveQueuePlayhead(80.25, revision: 1),
              try await store.queueState()?.offset == 80.25 else {
            printFail(number, "QS-3: the first record or its playhead did not round-trip"); return false
        }
        let two = try await store.saveQueueState(record: second, offset: 0)
        let stale = try await store.saveQueuePlayhead(99, revision: one)
        guard two == 2, !stale, try await store.queueState() == StoredQueueState(revision: 2, record: second, offset: 0)
        else {
            printFail(number, "QS-3: a new record did not take the next revision, or a stale playhead landed")
            return false
        }
        let reopened = try await LibraryStore(url: url, appBuild: "verify")
        guard try await reopened.queueState() == StoredQueueState(revision: 2, record: second, offset: 0) else {
            printFail(number, "QS-3: the reopened store reads another queue state"); return false
        }
        printPass(number, "QS-3 the queue state round-trips byte for byte; each record takes the next revision; a "
            + "playhead lands only on its own revision (a stale one writes nothing); a reopen reads the same")
        return true
    } catch {
        printFail(number, "QS-3 threw: \(error)"); return false
    }
}

// MARK: - QS-4 — a failed write leaves the previous state whole

func checkQueueStateNoHalfWrite(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let kept = StoredQueueState(revision: 1, record: #"{"format":1,"slots":[]}"#, offset: 10)
        try await store.saveQueueState(record: kept.record, offset: 10)
        // The record is replaced first, then the playhead's CHECK refuses: the transaction rolls back whole.
        var refused = false
        do {
            try await store.saveQueueState(record: #"{"format":1,"slots":[{"track":{"id":1}}]}"#, offset: -1)
        } catch {
            refused = true
        }
        guard refused, try await store.queueState() == kept, try await store.integrityCheck() else {
            printFail(number, "QS-4: a write that failed half-way left a mix (or was not refused)"); return false
        }
        printPass(number, "QS-4 a write refused after replacing the record (the playhead's CHECK, same "
            + "transaction) leaves the previous record and playhead whole: a half write is impossible")
        return true
    } catch {
        printFail(number, "QS-4 threw: \(error)"); return false
    }
}

// MARK: - QS-5 — readers racing the writer never see a mix

/// A reader saw a record with another record's playhead.
private struct MixedQueueRead: Error {
    let state: StoredQueueState
}

func checkQueueStateNoMixedRead(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let writes = 400
        try await withDeadline("queue-state writer ‖ readers", seconds: 30) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for index in 1 ... writes {
                        // Record `index` carries its own number; its playheads are index and index + 0.5.
                        let revision = try await store.saveQueueState(record: "record \(index)", offset: Double(index))
                        _ = try await store.saveQueuePlayhead(Double(index) + 0.5, revision: revision)
                    }
                }
                for _ in 0 ..< 4 {
                    group.addTask {
                        for _ in 0 ..< writes {
                            guard let state = try await store.queueState() else { continue }
                            let index = Double(state.record.dropFirst("record ".count)) ?? -1
                            guard let offset = state.offset, offset == index || offset == index + 0.5 else {
                                throw MixedQueueRead(state: state)
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
        }
        guard try await store.queueState()?.revision == Int64(writes), try await store.integrityCheck() else {
            printFail(number, "QS-5: the writer's last record is not the stored one"); return false
        }
        printPass(number, "QS-5 \(writes) records and \(writes) playhead moves ‖ 4 readers: every read is one "
            + "record with its own playhead — never a mix")
        return true
    } catch let mixed as MixedQueueRead {
        printFail(number, "QS-5: a reader saw a mix: \(mixed.state)"); return false
    } catch {
        printFail(number, "QS-5 threw: \(error)"); return false
    }
}
