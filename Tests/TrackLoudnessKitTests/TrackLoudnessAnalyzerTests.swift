// ANALYZER — TrackLoudnessAnalyzer end to end on generated WAVs (Sprint EQ, EQ1c part 2;
// amendments item 3): the prefix first and then the whole track, the cache, latest-wins and the
// prefetch promotion, and a file that cannot be analysed — reported, logged once, never decoded
// again. The fixtures are written at run time into test-data/ (never /tmp). Each test keeps its
// analyzer alive until it has what it waits for: dropping the analyzer cancels its jobs. A test
// that needs a job still running holds it at its prefix (RecordingSink(holdingPrefixOf:)) rather
// than racing the decode.

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
        // The long job is held at its prefix: running, and it cannot finish until released. So the
        // second request decides whether it ends, not how fast the runner decodes 240 s (PR #94's
        // CI: a busy runner let the long job finish before the second request was handled).
        let sink = RecordingSink(holdingPrefixOf: longIdentity.token)
        let log = LogRecorder()
        let analyzer = TrackLoudnessAnalyzer(prefixSeconds: 2, log: log.record)
        analyzer.analyze(long, identity: longIdentity, as: .current, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.contains { $0.token == longIdentity.token } }
        analyzer.analyze(short, identity: shortIdentity, as: .current, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.contains { $0.isWhole && $0.token == shortIdentity.token } }
        // Released, the long job meets its cancellation at its next read and ends without a whole.
        sink.release()
        await log.wait(keeping: analyzer, forLineContaining: "'\(long.lastPathComponent)' — cancelled")
        #expect(!sink.holdExpired, "the long job's hold expired before the test released it")
        #expect(!sink.events.contains { $0.isWhole && $0.token == longIdentity.token })
    }

    @Test("ANALYZER-05: asking for the prefetched next track as the current one promotes its job")
    func prefetchPromoted() async throws {
        let url = try Fixtures.noise(named: "prefetch-promoted", seconds: 6)
        let other = try Fixtures.noise(named: "prefetch-promoted-other", seconds: 1)
        let identity = try #require(TrackIdentity(url: url))
        let otherIdentity = try #require(TrackIdentity(url: other))
        // The prefetch is held at its prefix: running, and it cannot finish until released.
        let sink = RecordingSink(holdingPrefixOf: identity.token)
        let log = LogRecorder()
        let analyzer = TrackLoudnessAnalyzer(prefixSeconds: 2, log: log.record)
        analyzer.analyze(other, identity: otherIdentity, as: .current, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.count(whole: otherIdentity.token) == 1 }
        analyzer.analyze(url, identity: identity, as: .next, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.contains { $0.token == identity.token } }
        analyzer.analyze(url, identity: identity, as: .current, sink: sink)
        // Requests are handled in order, so once the other track's cached profile comes again the
        // .current request has been handled, while the prefetch was still held.
        analyzer.analyze(other, identity: otherIdentity, as: .next, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.count(whole: otherIdentity.token) == 2 }
        sink.release()
        let events = await sink.wait(keeping: analyzer) { $0.count(whole: identity.token) >= 1 }
        #expect(!sink.holdExpired, "the prefetch's hold expired before the test released it")
        #expect(log.count(containing: "analysing '\(url.lastPathComponent)'") == 1)
        #expect(events.count(whole: identity.token) == 1)
    }

    @Test("ANALYZER-06: a prefetch that finished before its track became current is re-published from the cache")
    func finishedPrefetchRepublished() async throws {
        let url = try Fixtures.noise(named: "prefetch-finished", seconds: 6)
        let identity = try #require(TrackIdentity(url: url))
        let sink = RecordingSink()
        let log = LogRecorder()
        let analyzer = TrackLoudnessAnalyzer(prefixSeconds: 2, log: log.record)
        analyzer.analyze(url, identity: identity, as: .next, sink: sink)
        _ = await sink.wait(keeping: analyzer) { $0.count(whole: identity.token) == 1 }
        analyzer.analyze(url, identity: identity, as: .current, sink: sink)
        let events = await sink.wait(keeping: analyzer) { $0.count(whole: identity.token) >= 2 }
        let wholes = events.filter(\.isWhole)
        #expect(log.count(containing: "analysing") == 1)
        #expect(wholes.count == 2)
        #expect(Set(wholes.map(\.profile)).count == 1) // the same profile, so the engine's gain stays
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

/// Records what the analyzer publishes (it calls from its own threads). It can hold one track's
/// job at its prefix until `release()`, so a test knows that job is still running.
final class RecordingSink: TrackLoudnessSink, @unchecked Sendable {
    struct Event {
        let token: UInt64
        let isWhole: Bool
        let isFailure: Bool
        let seconds: Double
        let profile: ObjectIdentifier? // which profile handle; nil for a failure
    }

    private let lock = NSLock()
    private var recorded: [Event] = []
    private let gate = NSCondition()
    private var held: UInt64? // the token whose prefix waits for `release()`; nil once released
    private var expired = false // the hold gave up before `release()` — the test's premise broke

    /// `holdingPrefixOf`: a token whose job waits, after publishing its prefix, until `release()`.
    init(holdingPrefixOf held: UInt64? = nil) {
        self.held = held
    }

    var events: [Event] {
        lock.withLock { recorded }
    }

    func publishLoudnessProfile(_ profile: TrackLoudnessProfileHandle, token: UInt64) {
        let event = Event(token: token, isWhole: profile.info.wholeTrack, isFailure: false,
                          seconds: profile.info.analysedSeconds, profile: ObjectIdentifier(profile))
        lock.withLock { recorded.append(event) }
        guard !event.isWhole else { return }
        // This is the job's own thread (it decodes synchronously there); the coordinator stays
        // free. The hold lasts until `release()`: on a CI runner busy with the whole suite, the
        // requests the test sends meanwhile can take longer than any short deadline to be handled,
        // and a hold that quietly gave up let the prefetch finish early (ANALYZER-05, PR #91 run
        // 39208624633: two whole profiles). Bounded only against a real hang, and then recorded —
        // `holdExpired` fails the test instead of letting it count a broken interleaving.
        let hangLimit = Date().addingTimeInterval(300)
        gate.lock()
        while held == token {
            if !gate.wait(until: hangLimit) {
                expired = held == token
                break
            }
        }
        gate.unlock()
    }

    /// Whether a held prefix gave up waiting before `release()` (only on a real hang).
    var holdExpired: Bool {
        gate.lock()
        defer { gate.unlock() }
        return expired
    }

    func reportLoudnessAnalysisFailure(token: UInt64) {
        lock.withLock {
            recorded.append(Event(token: token, isWhole: false, isFailure: true, seconds: 0, profile: nil))
        }
    }

    /// Let the held job run on to the whole track.
    func release() {
        gate.lock()
        held = nil
        gate.broadcast()
        gate.unlock()
    }

    /// The events once `done` holds for them, keeping `analyzer` alive meanwhile (dropping it cancels
    /// its jobs). It waits as long as the analyzer needs: on a CI runner busy with the whole suite the
    /// analyzer's utility-QoS work can be starved past any short deadline, and a wait that gave up and
    /// returned would let the test assert on a half-finished state (ANALYZER-05 on PR #91 run
    /// 39166938434: a 30 s wait timed out, the hold was released early, two profiles came). If the
    /// state truly never comes, the test fails here, saying so — it never carries on.
    func wait(keeping _: TrackLoudnessAnalyzer,
              sourceLocation: SourceLocation = #_sourceLocation,
              until done: ([Event]) -> Bool) async -> [Event] {
        await waitUntil("the analyzer reached the awaited state", sourceLocation: sourceLocation) { done(events) }
        return events
    }
}

extension [RecordingSink.Event] {
    /// How many whole-track profiles were published for `token`.
    func count(whole token: UInt64) -> Int {
        count { $0.isWhole && $0.token == token }
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

    /// Wait, keeping `analyzer` alive, until a line contains `text`.
    func wait(keeping _: TrackLoudnessAnalyzer,
              sourceLocation: SourceLocation = #_sourceLocation,
              forLineContaining text: String) async {
        await waitUntil("a log line containing \"\(text)\"", sourceLocation: sourceLocation) {
            count(containing: text) > 0
        }
    }
}

/// Wait until `done` holds. Time only breaks a hang: after 300 s the test fails, naming `what`.
func waitUntil(_ what: String, sourceLocation: SourceLocation, _ done: () -> Bool) async {
    let hangLimit = ContinuousClock.now + .seconds(300)
    while !done() {
        if ContinuousClock.now >= hangLimit {
            Issue.record("\(what): not so after 300 s", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
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
