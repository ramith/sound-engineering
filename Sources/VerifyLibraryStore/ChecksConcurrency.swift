// ChecksConcurrency — case D (concurrency, design §6-D). Companion to main.swift.
//
// Covers: journal_mode=wal + busy_timeout verified set; concurrent readers; a
// single-writer + concurrent-readers SNAPSHOT-ISOLATION check (every read result ∈
// {pre,post}, never torn); SQLITE_BUSY handled (typed, not a crash); a bounded
// N-writes ‖ M-reads STRESS loop ending in PRAGMA integrity_check=ok + a Swift-side
// row-count ledger; and reader-survives-a-writer's-mid-transaction-abort (WAL replay).
//
// GENUINE concurrency needs multiple connections against the shared WAL file: within
// ONE actor every call serialises, so the readers/writer here are SEPARATE
// LibraryStore actor instances (each owns its own SQLiteConnection) opened on the
// same on-disk file — exactly the multi-connection WAL configuration the store's
// pragmas are designed for.
//
// BOUNDED: every concurrent phase runs under a wall-clock deadline; a phase that
// does not finish is a FAIL (a deadlock), never a skip.

import Foundation
import LibraryStore

/// The concurrent phases' wall-clock budget. Overrun ⇒ FAIL (deadlock), per §6-D.
private let concurrencyDeadlineSeconds: Double = 20.0

/// The two counts a snapshot read must always be one of (never in-between).
private struct SnapshotBounds {
    let pre: Int
    let post: Int
}

/// The outcome of the snapshot-isolation probe: the first torn count observed (nil
/// = none). A dedicated type so `withDeadline`'s "nil == timed out" is unambiguous
/// (a plain `Int?` would collide with "no torn value").
private struct SnapshotOutcome {
    let tornValue: Int?
}

// MARK: - D — concurrency

func checkConcurrency(number: Int, url: URL) async -> Bool {
    do {
        // Establish the schema once (a fresh, migrated store on the file).
        let primary = try await LibraryStore(url: url, appBuild: "verify")
        let rootID = try await primary.addRoot(URL(fileURLWithPath: "/Music/Conc"))

        guard try await checkPragmasSet(primary, number: number) else { return false }
        guard try await checkConcurrentReaders(url: url, number: number) else { return false }
        guard try await checkSnapshotIsolation(primary, url: url, number: number, rootID: rootID) else {
            return false
        }
        guard checkBusyHandled(url: url, number: number) else { return false }
        guard try await checkReaderSurvivesWriterAbort(primary, url: url, number: number) else { return false }
        guard try await checkStressLoop(primary, url: url, number: number, rootID: rootID) else { return false }

        printPass(number, "concurrency: WAL + busy_timeout set; concurrent readers OK; snapshot isolation "
            + "(reads ∈ {pre,post}, never torn); SQLITE_BUSY typed-handled; reader survives a writer's "
            + "mid-txn abort; stress N-writes ‖ M-reads → integrity_check=ok + row-count ledger reconciles")
        return true
    } catch {
        printFail(number, "concurrency threw: \(error)"); return false
    }
}

/// WAL + busy_timeout must be live on the store.
private func checkPragmasSet(_ store: LibraryStore, number: Int) async throws -> Bool {
    let journal = try await store.journalMode().lowercased()
    guard journal == "wal" else {
        printFail(number, "concurrency: journal_mode is '\(journal)', expected wal"); return false
    }
    guard try await store.busyTimeout() > 0 else {
        printFail(number, "concurrency: busy_timeout not set (> 0 required)"); return false
    }
    return true
}

/// Multiple reader connections (separate actor instances) read the same store
/// concurrently without error, under a deadline.
private func checkConcurrentReaders(url: URL, number: Int) async throws -> Bool {
    let completed = try await withDeadline(seconds: concurrencyDeadlineSeconds) {
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 4 {
                group.addTask {
                    let reader = try await LibraryStore(url: url, appBuild: "verify")
                    var total = 0
                    for _ in 0 ..< 50 {
                        total += try await reader.trackCount()
                    }
                    return total
                }
            }
            var done = 0
            for try await _ in group {
                done += 1
            }
            return done
        }
    }
    guard completed == 4 else {
        printFail(number, "concurrency: concurrent readers did not all complete within the deadline "
            + "(\(String(describing: completed))/4)")
        return false
    }
    return true
}

/// SNAPSHOT ISOLATION: with a known `pre` row count, a writer commits a batch to
/// reach `post` in ONE transaction while readers poll the count. Under WAL every
/// observed count must be EXACTLY `pre` or `post` — never an in-between (torn) value,
/// because the whole BEGIN IMMEDIATE…COMMIT is atomic to any reader's snapshot.
private func checkSnapshotIsolation(
    _ writer: LibraryStore, url: URL, number: Int, rootID: Int64
) async throws -> Bool {
    let pre = try await writer.trackCount()
    let batchSize = 200
    let bounds = SnapshotBounds(pre: pre, post: pre + batchSize)
    let batch = (0 ..< batchSize).map {
        makeScanned(path: "/Music/Conc/snap-\($0).flac", name: "snap-\($0)")
    }

    let outcome = try await withDeadline(seconds: concurrencyDeadlineSeconds) {
        try await runSnapshotProbe(writer: writer, url: url, batch: batch, rootID: rootID, bounds: bounds)
    }
    guard let outcome else {
        printFail(number, "snapshot isolation: did NOT complete within the deadline (deadlock)"); return false
    }
    if let torn = outcome.tornValue {
        printFail(number, "snapshot isolation: torn count \(torn) (not pre=\(bounds.pre) or post=\(bounds.post))")
        return false
    }
    guard try await writer.trackCount() == bounds.post else {
        printFail(number, "snapshot isolation: final count != post (\(bounds.post)); writer batch lost")
        return false
    }
    return true
}

/// The snapshot probe: one atomic writer batch racing four polling readers on
/// separate connections. Returns the first torn count any reader saw (nil = none).
private func runSnapshotProbe(
    writer: LibraryStore, url: URL, batch: [ScannedFile], rootID: Int64, bounds: SnapshotBounds
) async throws -> SnapshotOutcome {
    try await withThrowingTaskGroup(of: Int?.self) { group in
        // Writer: one atomic batch (a single BEGIN IMMEDIATE…COMMIT internally).
        group.addTask {
            let gen = try await writer.beginScanGeneration()
            _ = try await writer.upsert(batch, folderID: rootID, generation: gen)
            return nil
        }
        // Readers on separate connections: poll the count; report the first count
        // that is neither `pre` nor `post` (a torn read), else nil.
        for _ in 0 ..< 4 {
            group.addTask {
                let reader = try await LibraryStore(url: url, appBuild: "verify")
                for _ in 0 ..< 400 {
                    let seen = try await reader.trackCount()
                    if seen != bounds.pre, seen != bounds.post { return seen }
                }
                return nil
            }
        }
        var firstTorn: Int?
        for try await result in group where result != nil {
            firstTorn = result
        }
        return SnapshotOutcome(tornValue: firstTorn)
    }
}

/// SQLITE_BUSY is HANDLED as a typed error (not a crash): a connection with a tiny
/// busy_timeout that tries to take the write lock while another connection holds an
/// open write transaction either succeeds (if it got in first) or fails with a
/// typed BUSY — in NO case does it trap. We assert the typed-error path is reachable
/// and non-crashing.
private func checkBusyHandled(url: URL, number: Int) -> Bool {
    do {
        // Holder: a normal (5s) connection that opens and HOLDS a write transaction.
        let holder = try SQLiteConnection(path: url.path)
        defer { holder.close() }
        try holder.exec("BEGIN IMMEDIATE;")

        // Contender: a tiny-timeout connection; taking the write lock must fail fast
        // with a typed BUSY (not hang past our patience, not crash).
        let contender = try SQLiteConnection(path: url.path, busyTimeoutMillis: 50)
        defer { contender.close() }
        var sawBusy = false
        do {
            try contender.exec("BEGIN IMMEDIATE;")
            // If it somehow acquired the lock, release it so the holder can roll back.
            try? contender.exec("ROLLBACK;")
        } catch let error as SQLiteError {
            sawBusy = error.isBusy
            guard sawBusy else {
                printFail(number, "SQLITE_BUSY: contender threw a non-BUSY error: \(error)"); return false
            }
        }
        try holder.exec("ROLLBACK;")
        guard sawBusy else {
            printFail(number, "SQLITE_BUSY: expected a typed BUSY while the write lock was held")
            return false
        }
        return true
    } catch {
        printFail(number, "SQLITE_BUSY probe threw unexpectedly: \(error)"); return false
    }
}

/// Reader survives a writer's MID-TRANSACTION ABORT (WAL replay): a raw writer
/// connection begins a transaction, inserts a row, then ROLLBACKs. A reader on
/// another connection reads afterwards and sees NEITHER the aborted row nor any
/// corruption (integrity_check ok).
private func checkReaderSurvivesWriterAbort(
    _ store: LibraryStore, url: URL, number: Int
) async throws -> Bool {
    let before = try await store.trackCount()
    let abortPath = "/Music/Conc/aborted-\(UUID().uuidString).flac"

    // Writer connection: begin, insert, abort — all on a raw connection.
    let writer = try SQLiteConnection(path: url.path)
    defer { writer.close() }
    try writer.exec("BEGIN IMMEDIATE;")
    let insert = try writer.prepare(
        "INSERT INTO tracks(url, name, format, file_size, mtime, date_added) "
            + "VALUES (?, 'aborted', 'FLAC', 1, 1, 1);"
    )
    try insert.bind(abortPath, at: 1)
    _ = try insert.step()
    insert.finalize()
    try writer.exec("ROLLBACK;")

    // Reader survives + sees the pre-abort state; integrity intact.
    let reader = try await LibraryStore(url: url, appBuild: "verify")
    guard try await reader.trackCount() == before else {
        printFail(number, "abort: reader saw an aborted row (count changed)"); return false
    }
    guard try await reader.track(url: URL(fileURLWithPath: abortPath)) == nil else {
        printFail(number, "abort: the aborted row is queryable — rollback did not take"); return false
    }
    guard try await reader.integrityCheck() else {
        printFail(number, "abort: integrity_check failed after a writer's rollback"); return false
    }
    return true
}

/// Bounded stress: 500 writes ‖ 2000 reads across 4 reader tasks. Ends with a
/// Swift-side row-count ledger (baseline + writes-committed == final count) AND
/// PRAGMA integrity_check=ok. Overrun ⇒ FAIL (deadlock).
private func checkStressLoop(
    _ writer: LibraryStore, url: URL, number: Int, rootID: Int64
) async throws -> Bool {
    let baseline = try await writer.trackCount()
    let writeCount = 500
    let readsPerReader = 500 // × 4 readers = 2000 reads

    let finished = try await withDeadline(seconds: concurrencyDeadlineSeconds) {
        try await runStress(writer: writer, url: url, rootID: rootID,
                            writeCount: writeCount, readsPerReader: readsPerReader)
        return true
    }
    guard finished == true else {
        printFail(number, "stress: N-writes ‖ M-reads did NOT complete within "
            + "\(concurrencyDeadlineSeconds)s — treated as a deadlock (FAIL)"); return false
    }

    // Row-count ledger: every distinct write landed exactly once.
    let final = try await writer.trackCount()
    guard final == baseline + writeCount else {
        printFail(number, "stress: row-count ledger mismatch — final \(final) != baseline "
            + "\(baseline) + \(writeCount) writes"); return false
    }
    guard try await writer.integrityCheck() else {
        printFail(number, "stress: PRAGMA integrity_check NOT ok after the stress loop"); return false
    }
    return true
}

/// The stress body: one writer performing `writeCount` distinct upserts alongside
/// four readers each doing `readsPerReader` count + list reads on their own connection.
private func runStress(
    writer: LibraryStore, url: URL, rootID: Int64, writeCount: Int, readsPerReader: Int
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for index in 0 ..< writeCount {
                let file = makeScanned(path: "/Music/Conc/stress-\(index).flac", name: "stress-\(index)")
                let gen = try await writer.beginScanGeneration()
                _ = try await writer.upsert([file], folderID: rootID, generation: gen)
            }
        }
        for _ in 0 ..< 4 {
            group.addTask {
                let reader = try await LibraryStore(url: url, appBuild: "verify")
                for _ in 0 ..< readsPerReader {
                    _ = try await reader.trackCount()
                    _ = try await reader.allTracks(sortedBy: .name)
                }
            }
        }
        try await group.waitForAll()
    }
}
