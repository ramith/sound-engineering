// ANALYZER — TrackLoudnessAnalyzer end to end on generated WAVs (Sprint EQ, EQ1c part 2;
// amendments item 3): the prefix first and then the whole track, the cache, latest-wins and the
// prefetch promotion, and a file that cannot be analysed — reported, logged once, never decoded
// again. The fixtures are written at run time into test-data/ (never /tmp). Each test keeps its
// analyzer alive until it has what it waits for: dropping the analyzer cancels its jobs.

import AVFoundation
import Foundation
import Testing
@testable import TrackLoudnessKit

@Suite("TrackLoudnessAnalyzer — prefix then whole, cache, latest-wins, failure")
struct TrackLoudnessAnalyzerTests {
    @Test("ANALYZER-01: the prefix (~25 s) is published first, then the whole track")
    func prefixThenWhole() async throws {
        let url = try Fixtures.noise(named: "prefix-then-whole", seconds: 40)
        let identity = try #require(TrackIdentity(url: url))
        let sink = RecordingSink()
        let analyzer = TrackLoudnessAnalyzer(log: { _ in })
        analyzer.analyze(url, identity: identity, as: .current, sink: sink)
        let events = await sink.wait(keeping: analyzer) { $0.contains { $0.isWhole } }
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.token == identity.token })
        let prefix = try #require(events.first)
        let whole = try #require(events.last)
        #expect(!prefix.isWhole && abs(prefix.seconds - 25) < 2)
        #expect(whole.isWhole && abs(whole.seconds - 40) < 0.5)
    }

    @Test("ANALYZER-02: a cached track is re-published at once — the whole profile, no second decode")
    func cacheHit() async throws {
        let url = try Fixtures.noise(named: "cache-hit", seconds: 8)
        let identity = try #require(TrackIdentity(url: url))
        let sink = RecordingSink()
        let log = LogRecorder()
        let analyzer = TrackLoudnessAnalyzer(log: log.record)
        analyzer.analyze(url, identity: identity, as: .current, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.count { $0.isWhole } == 1 }
        analyzer.analyze(url, identity: identity, as: .next, sink: sink)
        let events = await sink.wait(keeping: analyzer) { $0.count { $0.isWhole } == 2 }
        #expect(events.count { $0.isWhole } == 2)
        #expect(log.count(containing: "analysing") == 1)
    }

    @Test("ANALYZER-03: a file that cannot be analysed is reported (every time), logged once, decoded once")
    func failureReportedNeverRetried() async throws {
        let url = try Fixtures.garbage(named: "not-audio")
        let identity = try #require(TrackIdentity(url: url))
        let sink = RecordingSink()
        let log = LogRecorder()
        let analyzer = TrackLoudnessAnalyzer(log: log.record)
        analyzer.analyze(url, identity: identity, as: .current, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.count { $0.isFailure } == 1 }
        analyzer.analyze(url, identity: identity, as: .next, sink: sink)
        let events = await sink.wait(keeping: analyzer) { $0.count { $0.isFailure } == 2 }
        #expect(events.count { $0.isFailure } == 2)
        #expect(events.allSatisfy { $0.isFailure && $0.token == identity.token })
        #expect(log.count(containing: "analysing") == 1)
        #expect(log.count(containing: "cannot analyse") == 1)
    }

    @Test("ANALYZER-04: latest wins — a new current track cancels the previous one's job")
    func latestWins() async throws {
        let long = try Fixtures.noise(named: "latest-wins-long", seconds: 240, channels: 1)
        let short = try Fixtures.noise(named: "latest-wins-short", seconds: 6)
        let longIdentity = try #require(TrackIdentity(url: long))
        let shortIdentity = try #require(TrackIdentity(url: short))
        let sink = RecordingSink()
        let analyzer = TrackLoudnessAnalyzer(log: { _ in })
        analyzer.analyze(long, identity: longIdentity, as: .current, sink: sink)
        analyzer.analyze(short, identity: shortIdentity, as: .current, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.contains { $0.isWhole && $0.token == shortIdentity.token } }
        // Had the long job survived, it could finish in this time.
        _ = await sink.wait(keeping: analyzer, for: .milliseconds(500)) { _ in false }
        #expect(!sink.events.contains { $0.isWhole && $0.token == longIdentity.token })
    }

    @Test("ANALYZER-05: asking for the prefetched next track as the current one promotes its job")
    func prefetchPromoted() async throws {
        let url = try Fixtures.noise(named: "prefetch-promoted", seconds: 30)
        let identity = try #require(TrackIdentity(url: url))
        let sink = RecordingSink()
        let log = LogRecorder()
        let analyzer = TrackLoudnessAnalyzer(log: log.record)
        analyzer.analyze(url, identity: identity, as: .next, sink: sink)
        analyzer.analyze(url, identity: identity, as: .current, sink: sink)
        let events = await sink.wait(keeping: analyzer) { $0.contains { $0.isWhole } }
        #expect(log.count(containing: "analysing") == 1)
        #expect(events.count { $0.isWhole } == 1)
    }

    @Test("IDENTITY-01: the same file keeps its token; a rewritten file gets a new one; never 0")
    func identityToken() throws {
        let url = try Fixtures.noise(named: "identity", seconds: 1)
        let first = try #require(TrackIdentity(url: url))
        #expect(TrackIdentity(url: url) == first)
        #expect(first.token != 0)
        _ = try Fixtures.noise(named: "identity", seconds: 2)
        let rewritten = try #require(TrackIdentity(url: url))
        #expect(rewritten != first && rewritten.token != first.token)
        #expect(TrackIdentity(url: Fixtures.directory.appendingPathComponent("absent.wav")) == nil)
    }
}

// MARK: - Support

/// Records what the analyzer publishes (it calls from its own threads).
final class RecordingSink: TrackLoudnessSink, @unchecked Sendable {
    struct Event {
        let token: UInt64
        let isWhole: Bool
        let isFailure: Bool
        let seconds: Double
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    var events: [Event] {
        lock.withLock { recorded }
    }

    func publishLoudnessProfile(_ profile: TrackLoudnessProfileHandle, token: UInt64) {
        let event = Event(token: token, isWhole: profile.info.wholeTrack, isFailure: false,
                          seconds: profile.info.analysedSeconds)
        lock.withLock { recorded.append(event) }
    }

    func reportLoudnessAnalysisFailure(token: UInt64) {
        lock.withLock { recorded.append(Event(token: token, isWhole: false, isFailure: true, seconds: 0)) }
    }

    /// The events once `done` holds for them (or after `limit`), keeping `analyzer` alive meanwhile
    /// (dropping it cancels its jobs).
    func wait(keeping _: TrackLoudnessAnalyzer,
              for limit: Duration = .seconds(30),
              until done: ([Event]) -> Bool) async -> [Event] {
        let deadline = ContinuousClock.now + limit
        while !done(events), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return events
    }
}

/// Collects the analyzer's log lines.
final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    var record: @Sendable (String) -> Void {
        { [self] line in lock.withLock { lines.append(line) } }
    }

    func count(containing text: String) -> Int {
        lock.withLock { lines.count { $0.contains(text) } }
    }
}

/// Generated audio fixtures, written into test-data/track-loudness-kit/.
enum Fixtures {
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TrackLoudnessKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the repository
        .appendingPathComponent("test-data/track-loudness-kit", isDirectory: true)

    /// `seconds` of seeded noise, 16-bit PCM at 48 kHz.
    static func noise(named name: String, seconds: Double, channels: AVAudioChannelCount = 2) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).wav")
        try? FileManager.default.removeItem(at: url)
        let rate = 48000.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let chunk: AVAudioFrameCount = 48000
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk))
        var state: UInt32 = 0x9E37_79B9
        var remaining = AVAudioFrameCount(seconds * rate)
        while remaining > 0 {
            let frames = min(chunk, remaining)
            buffer.frameLength = frames
            for channel in 0 ..< Int(channels) {
                let samples = try #require(buffer.floatChannelData?[channel])
                for frame in 0 ..< Int(frames) {
                    state ^= state << 13
                    state ^= state >> 17
                    state ^= state << 5
                    samples[frame] = 0.1 * (Float(state) / Float(UInt32.max) - 0.5)
                }
            }
            try file.write(from: buffer)
            remaining -= frames
        }
        return url
    }

    /// A `.wav` that is not audio.
    static func garbage(named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).wav")
        try Data((0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: url)
        return url
    }
}
