import AudioDSP
@preconcurrency import AVFoundation
import Foundation

/// Where the analyzer's results go: the live engine (the playback bridge, through the AU's C-ABI).
public protocol TrackLoudnessSink: Sendable {
    /// A loudness profile for `token`: the prefix first, then the whole track. The same whole
    /// profile can come again: every request is answered, so a prefetch that finished before its
    /// track became current is published again, from the cache, when it does. A repeat must
    /// change nothing (the engine's gain does not move for it).
    func publishLoudnessProfile(_ profile: TrackLoudnessProfileHandle, token: UInt64)
    /// `token` could not be analysed at all: the engine falls back to its running estimate.
    func reportLoudnessAnalysisFailure(token: UInt64)
}

/// TrackLoudnessAnalyzer — the one owner of track loudness analysis (Sprint EQ, EQ1c part 2;
/// amendments item 3, engine-plan §4.2).
///
/// It decodes a track a second time with `AVAudioFile`, off the audio path at utility QoS, and
/// streams the PCM into the C++ profiler (TrackLoudnessBridge.h). The first ~25 s are published
/// as a PREFIX at once, so the loudness-neutral EQ gain is right within a moment of the track
/// starting; the stream then runs on to the WHOLE track, which the engine glides to slowly.
///
/// - At most two jobs: the current track and the next (gapless prefetch). A new request for a
///   role replaces (cancels) that role's job — latest wins; asking for the next track as the
///   current one promotes its job, while it runs, instead of restarting it. A prefetch that has
///   already finished is answered from the cache instead (the usual case: the next track becomes
///   current minutes after its prefetch), so its whole profile is published twice.
/// - A cache keyed by file identity (path + size + mtime) re-publishes a whole-track profile at
///   once, within a byte budget (least recently used first out).
/// - A file that cannot be analysed is reported to the engine (which estimates from the audio as
///   it plays), logged once, and never decoded again: later requests just re-report it.
/// - No analysis in Pure Mode: the bridge never asks for it there.
///
/// Requests are taken in order from any thread (an internal stream); the work runs elsewhere.
public final class TrackLoudnessAnalyzer: Sendable {
    /// Which job a request is for.
    public enum Role: Sendable {
        case current
        case next
    }

    private enum Request: Sendable {
        case analyze(URL, TrackIdentity, Role, any TrackLoudnessSink)
        case cancel(Role?)
    }

    private let inbox: AsyncStream<Request>.Continuation

    /// `prefixSeconds`: the prefix published first; `cacheBudgetBytes`: the profile cache's bound;
    /// `log`: one line per state change (analysing, analysed, failed).
    public init(prefixSeconds: Double = 25.0,
                cacheBudgetBytes: Int = 64 << 20,
                log: @escaping @Sendable (String) -> Void) {
        let (stream, continuation) = AsyncStream.makeStream(of: Request.self)
        inbox = continuation
        let coordinator = Coordinator(prefixSeconds: prefixSeconds, cacheBudgetBytes: cacheBudgetBytes, log: log)
        Task.detached(priority: .utility) {
            for await request in stream {
                switch request {
                case let .analyze(url, identity, role, sink):
                    await coordinator.analyze(url, identity: identity, as: role, sink: sink)
                case let .cancel(role):
                    await coordinator.cancel(role)
                }
            }
            await coordinator.cancel(nil)
        }
    }

    deinit {
        inbox.finish()
    }

    /// Analyse the file at `url` (whose identity is `identity`) as the current or next track,
    /// publishing to `sink`. Returns at once.
    public func analyze(_ url: URL, identity: TrackIdentity, as role: Role, sink: any TrackLoudnessSink) {
        inbox.yield(.analyze(url, identity, role, sink))
    }

    /// Cancel the job for `role`, or every job (`nil`: a stop, or Pure Mode). Returns at once.
    public func cancel(_ role: Role?) {
        inbox.yield(.cancel(role))
    }
}

// MARK: - The coordinator (jobs, cache, failures)

private actor Coordinator {
    private struct Job {
        let id: UInt64
        let identity: TrackIdentity
        let task: Task<Void, Never>
    }

    private struct Cached {
        let profile: TrackLoudnessProfileHandle
        var lastUse: UInt64
    }

    private let prefixSeconds: Double
    private let cacheBudgetBytes: Int
    private let log: @Sendable (String) -> Void
    private var jobs: [TrackLoudnessAnalyzer.Role: Job] = [:]
    private var nextJobID: UInt64 = 0
    private var cache: [TrackIdentity: Cached] = [:]
    private var cachedBytes = 0
    private var useClock: UInt64 = 0
    private var failed: Set<TrackIdentity> = []

    init(prefixSeconds: Double, cacheBudgetBytes: Int, log: @escaping @Sendable (String) -> Void) {
        self.prefixSeconds = prefixSeconds
        self.cacheBudgetBytes = cacheBudgetBytes
        self.log = log
    }

    func analyze(_ url: URL,
                 identity: TrackIdentity,
                 as role: TrackLoudnessAnalyzer.Role,
                 sink: any TrackLoudnessSink) {
        if jobs[role]?.identity == identity {
            return // already on it
        }
        if role == .current, let next = jobs[.next], next.identity == identity {
            jobs[.current]?.task.cancel()
            jobs[.current] = next // the prefetch becomes the current job — no restart
            jobs[.next] = nil
            return
        }
        jobs[role]?.task.cancel() // latest wins
        jobs[role] = nil
        if role == .next, jobs[.current]?.identity == identity {
            return // the current job already covers it
        }
        if var hit = cache[identity] {
            useClock += 1
            hit.lastUse = useClock
            cache[identity] = hit
            sink.publishLoudnessProfile(hit.profile, token: identity.token)
            return
        }
        if failed.contains(identity) {
            sink.reportLoudnessAnalysisFailure(token: identity.token) // never decoded again
            return
        }
        start(url, identity: identity, as: role, sink: sink)
    }

    func cancel(_ role: TrackLoudnessAnalyzer.Role?) {
        let roles: [TrackLoudnessAnalyzer.Role] = role.map { [$0] } ?? [.current, .next]
        for each in roles {
            jobs[each]?.task.cancel()
            jobs[each] = nil
        }
    }

    private func start(_ url: URL,
                       identity: TrackIdentity,
                       as role: TrackLoudnessAnalyzer.Role,
                       sink: any TrackLoudnessSink) {
        nextJobID += 1
        let id = nextJobID
        let token = identity.token
        let prefixSeconds = prefixSeconds
        log("loudness: analysing '\(url.lastPathComponent)'")
        let task = Task.detached(priority: .utility) { [weak self] in
            let outcome = TrackLoudnessDecoder.decode(url, prefixSeconds: prefixSeconds) { prefix in
                sink.publishLoudnessProfile(prefix, token: token)
            }
            await self?.finished(id, identity: identity, url: url, outcome: outcome, sink: sink)
        }
        jobs[role] = Job(id: id, identity: identity, task: task)
    }

    private func finished(_ id: UInt64,
                          identity: TrackIdentity,
                          url: URL,
                          outcome: TrackLoudnessDecoder.Outcome,
                          sink: any TrackLoudnessSink) {
        for (role, job) in jobs where job.id == id {
            jobs[role] = nil
        }
        let name = url.lastPathComponent
        switch outcome {
        case let .whole(profile):
            store(profile, for: identity)
            sink.publishLoudnessProfile(profile, token: identity.token)
            log("loudness: analysed '\(name)' — \(String(format: "%.1f", profile.info.analysedSeconds)) s, "
                + "\(String(format: "%.1f", profile.info.sourceLoudnessLufs)) LUFS")
        case let .prefixOnly(reason):
            log("loudness: '\(name)' — \(reason) after the prefix; keeping the prefix")
        case .cancelled:
            log("loudness: '\(name)' — cancelled")
        case let .failed(reason):
            failed.insert(identity)
            sink.reportLoudnessAnalysisFailure(token: identity.token)
            log("loudness: cannot analyse '\(name)' (\(reason)) — estimating from the audio as it plays")
        }
    }

    private func store(_ profile: TrackLoudnessProfileHandle, for identity: TrackIdentity) {
        useClock += 1
        if let old = cache.updateValue(Cached(profile: profile, lastUse: useClock), forKey: identity) {
            cachedBytes -= old.profile.bytes
        }
        cachedBytes += profile.bytes
        while cachedBytes > cacheBudgetBytes, cache.count > 1,
              let oldest = cache.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            cachedBytes -= oldest.value.profile.bytes
            cache[oldest.key] = nil
        }
    }
}

// MARK: - The decode → profile pipeline

/// One track's analysis: `AVAudioFile` → the C++ profiler, prefix then whole.
enum TrackLoudnessDecoder {
    enum Outcome: Sendable {
        case whole(TrackLoudnessProfileHandle)
        case prefixOnly(String) // the read failed after the prefix was published
        case cancelled
        case failed(String)
    }

    /// Decode `url` and profile it, calling `onPrefix` once the first `prefixSeconds` are in (not
    /// for a shorter track). Checks for cancellation between reads.
    static func decode(_ url: URL,
                       prefixSeconds: Double,
                       onPrefix: (TrackLoudnessProfileHandle) -> Void) -> Outcome {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let source: DecodeSource
        switch DecodeSource.open(url) {
        case let .success(opened):
            source = opened
        case let .failure(failure):
            return .failed(failure.reason)
        }
        defer { asLoudnessProfilerDestroy(source.profiler) }
        let streamed = source.stream(prefixSeconds: prefixSeconds, onPrefix: onPrefix)
        if streamed.cancelled {
            return .cancelled
        }
        // The whole track — or, after a failed read with no prefix out, whatever was analysed.
        if let error = streamed.error, streamed.prefixed {
            return .prefixOnly(error)
        }
        if let whole = TrackLoudnessProfileHandle(taking: asLoudnessProfilerFinishFull(source.profiler)) {
            return .whole(whole)
        }
        return .failed(streamed.error ?? "shorter than one 400 ms block")
    }
}

/// Why a track could not be opened for analysis.
private struct DecodeFailure: Error {
    let reason: String
}

/// How a decode stream ended.
private struct DecodeStream {
    var prefixed = false
    var cancelled = false
    var error: String?
}

/// One read's result.
private enum DecodeChunk {
    case data
    case end
    case error(String)
}

/// An opened track: the file, its profiler (destroyed by the caller) and the decode buffer.
private struct DecodeSource {
    /// Frames per read.
    static let chunkFrames: AVAudioFrameCount = 65536

    let file: AVAudioFile
    let profiler: OpaquePointer
    let buffer: AVAudioPCMBuffer

    static func open(_ url: URL) -> Result<DecodeSource, DecodeFailure> {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            return .failure(DecodeFailure(reason: "cannot open: \(error.localizedDescription)"))
        }
        let format = file.processingFormat
        let tag = format.channelLayout?.layoutTag ?? kAudioChannelLayoutTag_Unknown
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return .failure(DecodeFailure(reason: "no decode buffer"))
        }
        guard let profiler = asLoudnessProfilerCreate(format.sampleRate, format.channelCount, tag) else {
            return .failure(DecodeFailure(reason: "\(Int(format.sampleRate)) Hz × \(format.channelCount) ch is "
                    + "outside the profiler"))
        }
        return .success(DecodeSource(file: file, profiler: profiler, buffer: buffer))
    }

    /// Feed the whole file, publishing the prefix once `prefixSeconds` are in.
    func stream(prefixSeconds: Double, onPrefix: (TrackLoudnessProfileHandle) -> Void) -> DecodeStream {
        let prefixFrames = AVAudioFramePosition(prefixSeconds * file.processingFormat.sampleRate)
        var streamed = DecodeStream()
        var fed: AVAudioFramePosition = 0
        while !Task.isCancelled {
            switch readChunk() {
            case .end:
                return streamed
            case let .error(reason):
                streamed.error = reason
                return streamed
            case .data:
                fed += AVAudioFramePosition(buffer.frameLength)
            }
            if !streamed.prefixed, fed >= prefixFrames,
               let prefix = TrackLoudnessProfileHandle(taking: asLoudnessProfilerFinishPrefix(profiler)) {
                streamed.prefixed = true
                onPrefix(prefix)
            }
        }
        streamed.cancelled = true
        return streamed
    }

    /// Read the next chunk into `buffer` and feed it to the profiler.
    private func readChunk() -> DecodeChunk {
        if file.framePosition >= file.length {
            return .end // a read AT the end throws rather than returning 0 frames
        }
        do {
            try file.read(into: buffer)
        } catch {
            return .error("the read failed: \(error.localizedDescription)")
        }
        if buffer.frameLength == 0 {
            return .end
        }
        return feedBuffer() ? .data : .error("the decoder produced non-finite samples")
    }

    /// Feed the buffer (planar float32) to the profiler.
    private func feedBuffer() -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let count = Int(buffer.format.channelCount)
        let pointers: [UnsafePointer<Float>?] = (0 ..< count).map { UnsafePointer(channels[$0]) }
        return pointers.withUnsafeBufferPointer { list in
            asLoudnessProfilerFeed(profiler, list.baseAddress, UInt32(count), buffer.frameLength)
        }
    }
}
