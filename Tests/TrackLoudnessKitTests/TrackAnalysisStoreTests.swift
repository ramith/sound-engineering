// STORE — the analysis store (R1.1-B W5, lane 3-A; level-and-fold "The store and the scheduler", M5, M6, N7;
// US-R1F-10 item 16): track-analysis.sqlite3 beside the library, keyed by the file's identity, rebuildable — another
// version or a payload that will not decode is "not analysed", a broken file is recreated (never
// eraseDatabaseOnSchemaChange) — its compact profiles LRU-capped, re-keyed after "Use this drive", kept across a
// relaunch. Each test owns its own folder.

import AudioDSP
import Foundation
import GRDB
import Testing
@testable import TrackLoudnessKit

@Suite("TrackAnalysisStore — keyed by identity, rebuildable, profiles capped, re-keyed", .timeLimit(.minutes(2)))
struct TrackAnalysisStoreTests {
    @Test("STORE-01: a record round-trips without its profiles; the profiles come by basis; a relaunch keeps both")
    func roundTrip() async throws {
        let folder = try StoreFolder()
        let analysis = try StoreFixtures.analysis(path: "/music/a.flac", profileBlocks: 3)
        do {
            let store = try TrackAnalysisStore(directory: folder.url)
            try await store.save(analysis)
            let read = try await store.analyses(for: [analysis.identity])
            var expected = analysis
            expected.profiles = analysis.profiles.map { _ in nil }
            #expect(read == [analysis.identity: expected])
            let profiles = try await store.profiles(for: analysis.identity, bases: [0, 1, 3])
            #expect(profiles == [0: analysis.profiles[0], 1: analysis.profiles[1], 3: analysis.profiles[3]])
        }
        let relaunched = try TrackAnalysisStore(directory: folder.url)
        #expect(try await relaunched.analyses(for: [analysis.identity]).count == 1)
        #expect(try await relaunched.profiles(for: analysis.identity, bases: [0]).count == 1)
        #expect(relaunched.url.lastPathComponent == "track-analysis.sqlite3")
    }

    @Test("STORE-02: another size or mtime at the same path is another file: not analysed; saving it replaces")
    func identity() async throws {
        let store = try TrackAnalysisStore(directory: StoreFolder().url)
        let old = try StoreFixtures.analysis(path: "/music/a.flac", size: 100, modified: 10)
        try await store.save(old)
        let edited = try StoreFixtures.analysis(path: "/music/a.flac", size: 100, modified: 11)
        let resized = try StoreFixtures.analysis(path: "/music/a.flac", size: 101, modified: 10)
        #expect(try await store.analyses(for: [edited.identity, resized.identity]).isEmpty)
        try await store.save(edited)
        #expect(try await store.analyses(for: [old.identity, edited.identity]).keys.sorted { $0.modified < $1.modified }
            == [edited.identity])
        #expect(try await store.profiles(for: old.identity, bases: [0]).isEmpty)
    }

    @Test("STORE-03: a record of another analysis version counts as not analysed, and the next save overwrites it")
    func version() async throws {
        let store = try TrackAnalysisStore(directory: StoreFolder().url)
        var stale = try StoreFixtures.analysis(path: "/music/v.flac")
        stale.version = Int(AS_TRACK_ANALYSIS_VERSION) + 1
        try await store.save(stale)
        #expect(try await store.analyses(for: [stale.identity]).isEmpty)
        #expect(try await store.profiles(for: stale.identity, bases: [0]).isEmpty)
        let fresh = try StoreFixtures.analysis(path: "/music/v.flac")
        try await store.save(fresh)
        #expect(try await store.analyses(for: [fresh.identity]).count == 1)
    }

    @Test("STORE-04: a payload that will not decode counts as not analysed, and the next save overwrites it")
    func undecodable() async throws {
        let folder = try StoreFolder()
        let analysis = try StoreFixtures.analysis(path: "/music/u.flac")
        let store = try TrackAnalysisStore(directory: folder.url)
        try await store.save(analysis)
        try await DatabaseQueue(path: store.url.path).write { db in
            try db.execute(sql: "UPDATE analysis SET payload = ?", arguments: [Data("not a record".utf8)])
        }
        #expect(try await store.analyses(for: [analysis.identity]).isEmpty)
        try await store.save(analysis)
        #expect(try await store.analyses(for: [analysis.identity]).count == 1)
    }

    @Test("STORE-05: a file that is not a database is recreated, with its -wal and -shm; the store then works")
    func brokenFile() async throws {
        let folder = try StoreFolder()
        let url = folder.url.appending(path: TrackAnalysisStore.fileName)
        try Data(repeating: 0xA5, count: 8192).write(to: url)
        try Data("stale wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("stale shm".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))
        let store = try TrackAnalysisStore(directory: folder.url)
        let analysis = try StoreFixtures.analysis(path: "/music/b.flac")
        try await store.save(analysis)
        #expect(try await store.analyses(for: [analysis.identity]).count == 1)
        let wal = try? String(contentsOf: URL(fileURLWithPath: url.path + "-wal"), encoding: .utf8)
        #expect(wal != "stale wal") // gone, or the store's own
    }

    @Test("STORE-06: profiles past the cap go least recently used first, basis by basis; the numbers stay")
    func profileCap() async throws {
        // Each fixture's profiles: 5 bases × (10 blocks × 4 bands × 2 bytes) = 5 × 80 bytes. A cap of 800 holds two.
        let store = try TrackAnalysisStore(directory: StoreFolder().url, profileBudgetBytes: 800)
        let all = [0, 1, 2, 3, 4]
        let first = try StoreFixtures.analysis(path: "/music/1.flac", profileBlocks: 10)
        let second = try StoreFixtures.analysis(path: "/music/2.flac", profileBlocks: 10)
        let third = try StoreFixtures.analysis(path: "/music/3.flac", profileBlocks: 10)
        try await store.save(first)
        try await store.save(second)
        _ = try await store.profiles(for: first.identity, bases: all) // a read is a use: first is now the newest
        try await store.save(third)
        #expect(try await store.profiles(for: second.identity, bases: all).isEmpty)
        #expect(try await store.profiles(for: first.identity, bases: all).count == 5)
        #expect(try await store.profiles(for: third.identity, bases: all).count == 5)
        #expect(try await store.analyses(for: [first.identity, second.identity, third.identity]).count == 3)
    }

    @Test("STORE-06b: a 5.1 track plays two bases (decoded, its fold's variant): the bases nobody reads go first")
    func profileCapByBasis() async throws {
        let store = try TrackAnalysisStore(directory: StoreFolder().url, profileBudgetBytes: 560) // 7 bases
        let played = try StoreFixtures.analysis(path: "/music/played.flac", profileBlocks: 10)
        let next = try StoreFixtures.analysis(path: "/music/next.flac", profileBlocks: 10)
        try await store.save(played)
        _ = try await store.profiles(for: played.identity, bases: [0, 2])
        try await store.save(next)
        #expect(try await store.profiles(for: played.identity, bases: [0, 1, 2, 3, 4]).keys.sorted() == [0, 2])
        #expect(try await store.profiles(for: next.identity, bases: [0, 1, 2, 3, 4]).count == 5)
    }

    @Test("STORE-07: 'Use this drive' moves the records whose file is at the new place with the same size and mtime")
    func rekey() async throws {
        let folder = try StoreFolder()
        let oldRoot = folder.url.appending(path: "Old Drive/Music", directoryHint: .isDirectory)
        let newRoot = folder.url.appending(path: "New Drive 1/Music", directoryHint: .isDirectory)
        for root in [oldRoot, newRoot] {
            try FileManager.default.createDirectory(at: root.appending(path: "Album"),
                                                    withIntermediateDirectories: true)
        }
        let kept = oldRoot.appending(path: "Album/kept.wav")
        let touched = oldRoot.appending(path: "Album/touched.wav")
        let gone = oldRoot.appending(path: "Album/gone.wav")
        for file in [kept, touched, gone] {
            try Data(repeating: 1, count: 64).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
                                                  ofItemAtPath: file.path)
        }
        let store = try TrackAnalysisStore(directory: folder.url)
        let identities = try [kept, touched, gone].map { try #require(TrackIdentity(url: $0)) }
        for identity in identities {
            try await store.save(StoreFixtures.analysis(identity: identity))
        }
        try FileManager.default.copyItem(at: kept, to: newRoot.appending(path: "Album/kept.wav"))
        try FileManager.default.copyItem(at: touched, to: newRoot.appending(path: "Album/touched.wav"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)],
                                              ofItemAtPath: newRoot.appending(path: "Album/touched.wav").path)
        let moved = try await store.rekey(root: oldRoot.path, to: newRoot.path)
        #expect(moved == 1)
        let keptThere = try #require(TrackIdentity(url: newRoot.appending(path: "Album/kept.wav")))
        let touchedThere = try #require(TrackIdentity(url: newRoot.appending(path: "Album/touched.wav")))
        #expect(try await store.analyses(for: [keptThere, touchedThere]).keys.map(\.path) == [keptThere.path])
        #expect(try await store.profiles(for: keptThere, bases: [0]).count == 1) // the profiles moved with it
        #expect(try await store.analyses(for: [identities[1], identities[2]]).count == 2) // the rest stay put
    }
}

/// A folder of the test's own under test-data/, removed when the test ends.
final class StoreFolder: Sendable {
    let url: URL

    init() throws {
        url = Fixtures.directory.appending(path: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

enum StoreFixtures {
    /// An analysis of a 5.1 file at `path` (no file needed): every number set, a histogram per basis, and a
    /// `profileBlocks`-block, 4-band profile per basis.
    static func analysis(path: String, size: UInt64 = 1234, modified: Double = 1_700_000_000,
                         profileBlocks: Int = 2) throws -> TrackAnalysis {
        try analysis(identity: .make(path: path, size: size, modified: modified), profileBlocks: profileBlocks)
    }

    static func analysis(identity: TrackIdentity, profileBlocks: Int = 2) -> TrackAnalysis {
        let bases = Int(AS_PROFILE_BASES)
        let profile = { (basis: Int) in
            TrackAnalysis.Profile(sampleRate: 48000, bandsPerOctave: 24, bandCount: 4, blockCount: profileBlocks,
                                  blockStrideHops: 1,
                                  powers: (0 ..< profileBlocks * 4).map { UInt16(truncatingIfNeeded: $0 * 7 + basis) })
        }
        return TrackAnalysis(
            version: Int(AS_TRACK_ANALYSIS_VERSION), identity: identity, channelCount: 6, roles: [1, 2, 3, 4, 5, 6],
            sourceRateHz: 44100, peakRateHz: 48000, durationSeconds: 201.5, integratedLufs: -14.25,
            truePeakDbtp: -0.75, headBlockLufs: -33.5, tailBlockLufs: -200, folds: true,
            foldedLufs: [-15.5, -15, -14.5, nil], foldedTruePeakDbtp: [0.25, 0.5, 1, nil],
            lfe: .init(activeBlocks: 120, lagMs: 1.5, lagPeak: 0.25, coherentShare: 0.1, medianR2: 0.2, p90R2: 0.4,
                       excess20Share: 0.75, explainGainDb: nil),
            histograms: (0 ..< bases).map { [.init(bin: UInt32(500 + $0), count: 3, energy: 0.125)] },
            profiles: (0 ..< bases).map(profile),
            analysedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }
}

extension TrackIdentity {
    /// An identity for a file that need not exist (through its Codable form: the type reads a real file's
    /// attributes otherwise).
    static func make(path: String, size: UInt64, modified: Double) throws -> TrackIdentity {
        let fields: [String: Any] = ["path": path, "size": size, "modified": modified]
        return try JSONDecoder().decode(TrackIdentity.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}
