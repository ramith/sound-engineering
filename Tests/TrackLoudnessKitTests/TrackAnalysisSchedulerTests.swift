// SCHED — the album analysis scheduler (R1.1-B W5, lane 3-A; level-and-fold "The store and the scheduler", §13.1;
// US-R1F-10 item 17): the QoS rule (the job due now at .utility; a job further ahead at .background while it would
// still finish in time there; one job at a time below twice real time), and the runner end to end on generated
// files — every file analysed and kept, a stored one skipped, a job that leaves the horizon cancelled, a failure
// tried once.

import Foundation
import RigKit
import Synchronization
import Testing
@testable import TrackLoudnessKit

@Suite("The analysis QoS rule: due now at utility, ahead at background if it fits", .timeLimit(.minutes(1)))
struct AnalysisQoSTests {
    /// 44.1 kHz stereo, and DXD 5.0 (352.8 kHz × 5): the cheapest and the dearest material measured.
    private static let cd = 44100.0 * 2
    private static let dxd = 352_800.0 * 5

    @Test("SCHED-01: the playing album and anything due within 10 minutes run at utility")
    func due() {
        let playing = AnalysisQoS.Work(startsIn: 0, remainingSeconds: 3600, samplesPerSecond: Self.cd)
        #expect(AnalysisQoS.qos(for: playing) == .utility)
        let soon = AnalysisQoS.Work(startsIn: 9 * 60, remainingSeconds: 600, samplesPerSecond: Self.cd)
        #expect(AnalysisQoS.qos(for: soon) == .utility)
    }

    @Test("SCHED-02: an album further ahead runs at background while it would finish there before it is due")
    func ahead() {
        // A 70-minute CD album an hour ahead: ~5 minutes of work at background (≈15× real time).
        let album = AnalysisQoS.Work(startsIn: 3600, remainingSeconds: 70 * 60, samplesPerSecond: Self.cd)
        #expect(AnalysisQoS.qos(for: album) == .background)
        // A 60-minute DXD 5.0 album an hour ahead: ~80 minutes at background — too late, so utility (≈4×).
        let hiRes = AnalysisQoS.Work(startsIn: 3600, remainingSeconds: 3600, samplesPerSecond: Self.dxd)
        #expect(AnalysisQoS.qos(for: hiRes) == .utility)
        // The same album 2 hours ahead with a short remainder fits at background.
        let rest = AnalysisQoS.Work(startsIn: 7200, remainingSeconds: 1200, samplesPerSecond: Self.dxd)
        #expect(AnalysisQoS.qos(for: rest) == .background)
    }

    @Test("SCHED-03: a job's own measured background speed replaces the model's")
    func measured() {
        var album = AnalysisQoS.Work(startsIn: 3600, remainingSeconds: 70 * 60, samplesPerSecond: Self.cd)
        album.measuredBackground = 0.5 // a slow Mac: 140 minutes of work at background
        #expect(AnalysisQoS.qos(for: album) == .utility)
        album.measuredBackground = 40
        #expect(AnalysisQoS.qos(for: album) == .background)
    }

    @Test("SCHED-04: two jobs at once; one when either of the first two would run under twice real time")
    func stopRule() {
        let cd = AnalysisQoS.Work(startsIn: 0, remainingSeconds: 3000, samplesPerSecond: Self.cd)
        #expect(AnalysisQoS.concurrency([cd, cd, cd]) == 2)
        var slow = cd
        slow.measuredUtility = 1.5
        #expect(AnalysisQoS.concurrency([cd, slow]) == 1)
        #expect(AnalysisQoS.concurrency([cd, cd, slow]) == 2) // the third is not running
        let dxdDue = AnalysisQoS.Work(startsIn: 0, remainingSeconds: 3000, samplesPerSecond: Self.dxd)
        #expect(AnalysisQoS.concurrency([dxdDue, cd]) == 2) // DXD at utility ≈ 3.7×
    }
}

@Suite("TrackAnalysisScheduler — the horizon's albums analysed and kept", .timeLimit(.minutes(3)))
struct TrackAnalysisSchedulerTests {
    /// What a scheduler reported.
    private final class Reports: Sendable {
        private let analysed = Mutex<[String]>([])
        private let refused = Mutex<[String]>([])
        private let lines = Mutex<[String]>([])

        func add(_ analysis: TrackAnalysis) {
            analysed.withLock { $0.append((analysis.identity.path as NSString).lastPathComponent) }
        }

        func fail(_ url: URL) {
            refused.withLock { $0.append(url.lastPathComponent) }
        }

        /// The files reported as not analysable, in the order reported.
        var failed: [String] {
            refused.withLock { $0 }
        }

        func log(_ line: String) {
            lines.withLock { $0.append(line) }
        }

        var names: [String] {
            analysed.withLock { $0 }
        }

        var log: [String] {
            lines.withLock { $0 }
        }
    }

    private static func make(_ store: TrackAnalysisStore, _ reports: Reports) -> TrackAnalysisScheduler {
        TrackAnalysisScheduler(store: store, log: { reports.log($0) }, onAnalysed: { reports.add($0) },
                               onFailed: { reports.fail($0) })
    }

    private static func files(_ prefix: String, count: Int, seconds: Double = 2) throws -> [URL] {
        try (0 ..< count).map { index in
            try ToneFixtures.write(named: "\(prefix)-\(index)", rate: 48000, channels: 2, seconds: seconds) { _, _ in
                0.05 * Float(index + 1)
            }
        }
    }

    @Test("SCHED-05: every file of the horizon's jobs is analysed and kept; a second pass analyses nothing")
    func analysesAndKeeps() async throws {
        let folder = try StoreFolder()
        let store = try TrackAnalysisStore(directory: folder.url)
        let reports = Reports()
        let scheduler = Self.make(store, reports)
        let album = try Self.files("sched-album", count: 3)
        let loose = try Self.files("sched-loose", count: 1)
        scheduler.setHorizon([.init(id: "album 1", files: album, startsIn: 0),
                              .init(id: "loose", files: loose, startsIn: 400)])
        try await until("the four files analysed") { reports.names.count == 4 }
        let identities = try (album + loose).map { try #require(TrackIdentity(url: $0)) }
        #expect(try await store.analyses(for: identities).count == 4)
        // The same horizon again: everything is in the store, so nothing is decoded; a new job proves the
        // scheduler went through the old ones first.
        let marker = try Self.files("sched-marker", count: 1)
        scheduler.setHorizon([.init(id: "album 1", files: album, startsIn: 0),
                              .init(id: "loose", files: loose, startsIn: 400),
                              .init(id: "marker", files: marker, startsIn: 800)])
        try await until("the marker analysed") { reports.names.contains("sched-marker-0.wav") }
        #expect(reports.names.count == 5)
    }

    @Test("SCHED-06: a job that leaves the horizon stops between tracks")
    func cancelled() async throws {
        let store = try TrackAnalysisStore(directory: StoreFolder().url)
        let reports = Reports()
        let scheduler = Self.make(store, reports)
        let long = try Self.files("sched-long", count: 24, seconds: 4)
        scheduler.setHorizon([.init(id: "long", files: long, startsIn: 0)])
        try await until("the first long track analysed") { !reports.names.isEmpty }
        scheduler.setHorizon([])
        let marker = try Self.files("sched-after", count: 1)
        scheduler.setHorizon([.init(id: "after", files: marker, startsIn: 0)])
        try await until("the next horizon's job analysed") { reports.names.contains("sched-after-0.wav") }
        let longDone = reports.names.filter { $0.hasPrefix("sched-long") }.count
        #expect(longDone < long.count) // it stopped: at most the track in flight finished after the cancel
    }

    @Test("SCHED-08: a file whose header is slow to read (a drive waking up) holds neither the scheduler nor a job")
    func slowHeaderRead() async throws {
        // Review N8: the header reads ran on the scheduler's actor, on the cooperative pool. A slow drive then held
        // a pool thread, and the actor with it: the jobs already running could not record their tracks.
        let store = try TrackAnalysisStore(directory: StoreFolder().url)
        let reports = Reports()
        let scheduler = Self.make(store, reports)
        let steady = try Self.files("sched-steady", count: 24, seconds: 4)
        scheduler.setHorizon([.init(id: "steady", files: steady, startsIn: 0)])
        try await until("the first steady track analysed") { !reports.names.isEmpty }
        let slow = try SlowFile(named: "sched-slow-drive")
        defer { slow.release() }
        scheduler.setHorizon([.init(id: "steady", files: steady, startsIn: 0),
                              .init(id: "slow", files: [slow.url], startsIn: 60)])
        try await until("every steady track analysed while the slow file's header is still being read",
                        cap: .seconds(30)) { reports.names.count == steady.count }
    }

    @Test("SCHED-09: a file it cannot analyse is reported once — not there, not audio, refused by the pass")
    func reportsWhatCannotBeAnalysed() async throws {
        // Its analysis is not coming: the coordinator stops the fold badge's "· measuring" for it.
        let store = try TrackAnalysisStore(directory: StoreFolder().url)
        let reports = Reports()
        let scheduler = Self.make(store, reports)
        let missing = Fixtures.directory.appending(path: "sched-missing-\(UUID().uuidString).wav") // never written
        let garbage = try Fixtures.garbage(named: "sched-not-audio")
        let refused = try TinyFlac.write(named: "sched-refused", blockSize: 128) // the decoder refuses it
        let good = try Self.files("sched-reported-good", count: 1)
        let unanalysable = Set([missing, garbage, refused].map(\.lastPathComponent))
        scheduler.setHorizon([.init(id: "mixed", files: [missing, garbage, refused, good[0]], startsIn: 0)])
        try await until("the good file analysed and the three reported") {
            reports.names.contains("sched-reported-good-0.wav") && Set(reports.failed) == unanalysable
        }
        #expect(reports.failed.count == 3)
        let marker = try Self.files("sched-reported-later", count: 1)
        scheduler.setHorizon([.init(id: "again", files: [missing, garbage, refused], startsIn: 0),
                              .init(id: "later", files: marker, startsIn: 600)])
        try await until("the later job analysed") { reports.names.contains("sched-reported-later-0.wav") }
        #expect(reports.failed.count == 3, "reported again: \(reports.failed)")
    }

    @Test("SCHED-07: a file that cannot be analysed is tried once, logged, and skipped after")
    func failure() async throws {
        let store = try TrackAnalysisStore(directory: StoreFolder().url)
        let reports = Reports()
        let scheduler = Self.make(store, reports)
        let broken = try TinyFlac.write(named: "sched-tiny-blocks", blockSize: 128) // the decoder refuses it
        let good = try Self.files("sched-good", count: 1)
        scheduler.setHorizon([.init(id: "mixed", files: [broken, good[0]], startsIn: 0)])
        try await until("the good file analysed") { reports.names.contains("sched-good-0.wav") }
        #expect(reports.log.filter { $0.contains("cannot analyse") }.count == 1)
        let marker = try Self.files("sched-later", count: 1)
        // Another job holding the same file: the failure is remembered, so it is not decoded again.
        scheduler.setHorizon([.init(id: "again", files: [broken], startsIn: 0),
                              .init(id: "later", files: marker, startsIn: 600)])
        try await until("the later job analysed") { reports.names.contains("sched-later-0.wav") }
        #expect(reports.log.filter { $0.contains("cannot analyse") }.count == 1)
    }
}

/// A named pipe standing in for a file on a drive that takes its time to answer: opening it for reading blocks until
/// `release()` gives it a writer; the read then meets its end at once (not audio).
final class SlowFile: Sendable {
    let url: URL

    init(named name: String) throws {
        url = Fixtures.directory.appending(path: "\(name)-\(UUID().uuidString).wav")
        guard mkfifo(url.path, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Let every open waiting on it through, and remove it.
    func release() {
        let writer = open(url.path, O_RDWR)
        unlink(url.path)
        if writer >= 0 {
            close(writer)
        }
    }
}
