// Break-it, R1.1-B sound half: the analysis store under a lock and a schema it does not know.

import Foundation
import GRDB
import RigKit
import SQLite3
import Testing
@testable import TrackLoudnessKit

@Suite("Break-it, sound: the analysis store locked, and from a newer build", .serialized, .timeLimit(.minutes(2)))
struct BreakItStoreTests {
    @Test("BI-S20: a store another connection holds locked is never deleted from under it")
    func lockedIsNotDeleted() async throws {
        let folder = try StoreFolder()
        let analysis = try StoreFixtures.analysis(path: "/music/kept.flac")
        let url = folder.url.appending(path: TrackAnalysisStore.fileName)
        do {
            let store = try TrackAnalysisStore(directory: folder.url)
            try await store.save(analysis)
        }
        // Another connection (another process, a tool) holds the file locked past the store's 5 s busy timeout.
        let inode = { (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int }
        let before = inode()
        var holder: OpaquePointer?
        try #require(sqlite3_open_v2(url.path, &holder, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close(holder) }
        try #require(sqlite3_exec(holder, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        // The open waits out the busy timeout (5 s): on a thread of its own, never one of the cooperative pool's.
        let opened = try await blocking("open the store another connection holds locked") {
            try? TrackAnalysisStore(directory: folder.url)
        }
        sqlite3_exec(holder, "ROLLBACK", nil, nil, nil)
        _ = opened
        #expect(inode() == before, "the store deleted the locked file and made a new one in its place")
        let reopened = try TrackAnalysisStore(directory: folder.url)
        let kept = try await reopened.analyses(for: [analysis.identity]).count
        #expect(kept == 1, "the records of the locked store are gone")
    }

    @Test("BI-S21: a store a newer build migrated further keeps its records (never erased on a schema change)")
    func newerSchemaIsNotErased() async throws {
        let folder = try StoreFolder()
        let analysis = try StoreFixtures.analysis(path: "/music/newer.flac")
        let url = folder.url.appending(path: TrackAnalysisStore.fileName)
        do {
            let store = try TrackAnalysisStore(directory: folder.url)
            try await store.save(analysis)
        }
        // A newer build's additive migration: a table and its migration's name.
        let newer = try DatabaseQueue(path: url.path)
        try await newer.write { db in
            try db.execute(sql: "CREATE TABLE future_column_store (path TEXT PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v2')")
        }
        try newer.close()
        let older = try TrackAnalysisStore(directory: folder.url)
        #expect(try await older.analyses(for: [analysis.identity]).count == 1,
                "an older build erased the newer build's store")
    }
}
