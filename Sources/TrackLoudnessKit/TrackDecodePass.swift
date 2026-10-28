import AudioDSP
import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - The one decode of a track (R1.1-B, level-and-fold §1.2)

/// One decode of a track with `AVAudioFile`, at its own rate, feeding up to two consumers chunk by chunk:
///
/// 1. today's −ΔL **profiler** at the SOURCE rate (TrackLoudnessBridge.h), whose prefix is published as soon as
///    the first `prefixSeconds` are in — before anything is converted, so the SRC never delays it (architect N12);
/// 2. the one **analysis pass** at the ENGINE rate (`EngineRateMeasurement`): the stream converted by the
///    Enhanced path's own converter (`StreamingResampler`, Apple's Mastering SRC) into F1's format — the file's
///    own channels in its own layout (`engineFormat(forSource:sampleRate:)`) — so every true peak is the one the
///    limiter will see. A source already at the engine's rate is fed as is (the app plays it straight through).
///
/// The track loudness analyzer runs it with the profiler only (today's cost); the analysis tool and the album
/// analysis run it with the measurement too. Not thread-safe: one job owns it.
struct TrackDecodePass {
    /// Frames per read.
    static let chunkFrames: AVAudioFrameCount = 65536

    let file: AVAudioFile
    let buffer: AVAudioPCMBuffer
    /// Today's profiler (destroyed by the owner), when profiling.
    let profiler: OpaquePointer?
    /// The analysis pass, when measuring.
    let measurement: EngineRateMeasurement?

    /// Open `url` for a decode that profiles (`profile`) and/or measures at `engineRate` (nil: no measurement).
    static func open(_ url: URL, profile: Bool, measureAt engineRate: Double?) -> Result<Self, DecodeFailure> {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            return .failure(DecodeFailure(reason: "cannot open: \(error.localizedDescription)"))
        }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return .failure(DecodeFailure(reason: "no decode buffer"))
        }
        var profiler: OpaquePointer?
        if profile {
            let tag = format.channelLayout?.layoutTag ?? kAudioChannelLayoutTag_Unknown
            guard let created = asLoudnessProfilerCreate(format.sampleRate, format.channelCount, tag) else {
                return .failure(DecodeFailure(reason: "\(Int(format.sampleRate)) Hz × \(format.channelCount) ch is "
                        + "outside the profiler"))
            }
            profiler = created
        }
        var measurement: EngineRateMeasurement?
        if let engineRate {
            switch EngineRateMeasurement.make(source: format, engineRate: engineRate) {
            case let .success(made):
                measurement = made
            case let .failure(failure):
                profiler.map(asLoudnessProfilerDestroy)
                return .failure(failure)
            }
        }
        return .success(TrackDecodePass(file: file, buffer: buffer, profiler: profiler, measurement: measurement))
    }

    /// Read the whole file: each chunk goes to the profiler first (publishing its prefix once `prefixSeconds`
    /// are in), then to the measurement. Checks `isCancelled` between reads.
    func stream(prefixSeconds: Double, isCancelled: () -> Bool,
                onPrefix: (TrackLoudnessProfileHandle) -> Void) -> DecodeStream {
        let prefixFrames = AVAudioFramePosition(prefixSeconds * file.processingFormat.sampleRate)
        var streamed = DecodeStream()
        var fed: AVAudioFramePosition = 0
        while !isCancelled() {
            switch readChunk(after: fed) {
            case .end:
                return streamed
            case let .error(reason):
                streamed.error = reason
                return streamed
            case .data:
                fed += AVAudioFramePosition(buffer.frameLength)
            }
            if let profiler, !streamed.prefixed, fed >= prefixFrames,
               let prefix = TrackLoudnessProfileHandle(taking: asLoudnessProfilerFinishPrefix(profiler)) {
                streamed.prefixed = true
                onPrefix(prefix)
            }
            if let measurement, let failure = measurement.feed(buffer) {
                streamed.error = failure
                return streamed
            }
            // A short read is the decoder's real end. E-AC-3, AC-3, ffmpeg-made MP3 and Vorbis files deliver up to
            // a few hundred frames fewer than `file.length` reports, and the read after the short one throws
            // rather than returning nothing (PASS-09).
            if buffer.frameLength < buffer.frameCapacity {
                return streamed
            }
        }
        streamed.cancelled = true
        return streamed
    }

    /// Read the next chunk (`framesRead` read so far) into `buffer` and feed it to the profiler.
    ///
    /// The position is counted here, never asked of the file: `AVAudioFile.framePosition` raises an uncaught
    /// NSException — fatal to the process — on a file its decoder refuses (a FLAC with blocks under 192 samples:
    /// the corpus's tiny-block FLAC; PASS-06), even before any read. Its read throws instead, which ends the job.
    private func readChunk(after framesRead: AVAudioFramePosition) -> DecodeChunk {
        if framesRead >= file.length {
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
        guard let profiler else { return .data }
        return Self.feed(buffer) { asLoudnessProfilerFeed(profiler, $0, $1, $2) }
            ? .data : .error("the decoder produced non-finite samples")
    }

    /// Hand a planar float32 buffer to a C feed (`channels`, count, frames).
    static func feed(_ buffer: AVAudioPCMBuffer,
                     into consume: (UnsafePointer<UnsafePointer<Float>?>?, UInt32, UInt32) -> Bool) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let count = Int(buffer.format.channelCount)
        let pointers: [UnsafePointer<Float>?] = (0 ..< count).map { UnsafePointer(channels[$0]) }
        return pointers.withUnsafeBufferPointer { consume($0.baseAddress, UInt32(count), buffer.frameLength) }
    }
}

/// Why a track could not be opened for analysis.
struct DecodeFailure: Error {
    let reason: String
}

/// How a decode stream ended.
struct DecodeStream {
    var prefixed = false
    var cancelled = false
    var error: String?
}

/// One read's result.
enum DecodeChunk {
    case data
    case end
    case error(String)
}

// MARK: - The engine-rate measurement

/// The one analysis pass's side of a decode: F1's format at the engine's rate, the Mastering converter when the
/// rates differ, and the C++ analyzer (`asTrackAnalyzer*`) fed the converted stream.
final class EngineRateMeasurement {
    let analyzer: OpaquePointer
    let roles: [UInt8]
    let sourceRate: Double
    private let resampler: StreamingResampler?

    private init(analyzer: OpaquePointer, roles: [UInt8], sourceRate: Double, resampler: StreamingResampler?) {
        self.analyzer = analyzer
        self.roles = roles
        self.sourceRate = sourceRate
        self.resampler = resampler
    }

    deinit {
        asTrackAnalyzerDestroy(analyzer)
    }

    static func make(source: AVAudioFormat, engineRate: Double) -> Result<EngineRateMeasurement, DecodeFailure> {
        guard let engine = engineFormat(forSource: source, sampleRate: engineRate) else {
            return .failure(DecodeFailure(reason: "\(source.channelCount) channels: wider than the engine carries"))
        }
        let roles = ChannelRoles.resolve(format: source)
        var resampler: StreamingResampler?
        if source.sampleRate != engineRate {
            guard let converter = StreamingResampler(from: source, to: engine) else {
                return .failure(DecodeFailure(reason: "no converter from \(Int(source.sampleRate)) Hz"))
            }
            resampler = converter
        }
        guard let analyzer = roles.withUnsafeBufferPointer({
            asTrackAnalyzerCreate(engineRate, UInt32($0.count), $0.baseAddress)
        }) else {
            return .failure(DecodeFailure(reason: "\(source.channelCount) channels at \(Int(engineRate)) Hz is "
                    + "outside the analyzer"))
        }
        return .success(EngineRateMeasurement(analyzer: analyzer, roles: roles, sourceRate: source.sampleRate,
                                              resampler: resampler))
    }

    /// Convert (when needed) and analyse one decoded chunk; the reason on a failure.
    func feed(_ buffer: AVAudioPCMBuffer) -> String? {
        guard let resampler else { return analyse(buffer) }
        do {
            return try analyse(resampler.convert(buffer, inputEnded: false).buffer)
        } catch {
            return "the converter failed: \(error.localizedDescription)"
        }
    }

    /// Flush the converter's held frames and finish the analysis.
    func finish() -> Result<AsTrackAnalysis, DecodeFailure> {
        if let resampler {
            guard let empty = AVAudioPCMBuffer(pcmFormat: resampler.inputFormat, frameCapacity: 1) else {
                return .failure(DecodeFailure(reason: "no flush buffer"))
            }
            let maxFlushes = 16 // the converter holds back ~13 ms; a few calls at most
            for _ in 0 ..< maxFlushes {
                do {
                    let chunk = try resampler.convert(empty, inputEnded: true)
                    if let failure = analyse(chunk.buffer) {
                        return .failure(DecodeFailure(reason: failure))
                    }
                    if chunk.endOfStream {
                        break
                    }
                } catch {
                    return .failure(DecodeFailure(reason: "the converter failed: \(error.localizedDescription)"))
                }
            }
        }
        var analysis = AsTrackAnalysis()
        guard asTrackAnalyzerFinish(analyzer, &analysis) else {
            return .failure(DecodeFailure(reason: "the analysis did not finish"))
        }
        analysis.sourceRateHz = sourceRate
        return .success(analysis)
    }

    private func analyse(_ buffer: AVAudioPCMBuffer) -> String? {
        guard buffer.frameLength > 0 else { return nil }
        return TrackDecodePass.feed(buffer) { asTrackAnalyzerFeed(analyzer, $0, $1, $2) }
            ? nil : "the converted stream had non-finite samples"
    }
}

// MARK: - The analysis pass (public)

/// The one analysis pass over a file (R1.1-B, level-and-fold §1.2): decode once, measure at the engine's rate,
/// and — optionally — profile at the source rate as the track loudness analyzer does. Synchronous and blocking:
/// run it off the main thread and off the cooperative pool (a decode is seconds of reads and DSP).
public enum TrackAnalysisPass {
    /// What a pass produced.
    public enum Outcome: Sendable {
        /// The analysis, and the whole-track −ΔL profile when profiling was asked for.
        case analysed(TrackAnalysis, profile: TrackLoudnessProfileHandle?)
        case cancelled
        case failed(String)
    }

    /// The engine's rate (the graph's).
    public static let engineRate = 48000.0

    /// Analyse the file at `url` (whose identity is `identity`) at `engineRate`. With `profile`, today's
    /// profiler runs too and its prefix goes to `onPrefix` once `prefixSeconds` are in, before the SRC.
    /// Checks `isCancelled` between reads.
    public static func analyse(_ url: URL, identity: TrackIdentity, engineRate: Double = engineRate,
                               profile: Bool = false, prefixSeconds: Double = 25,
                               isCancelled: () -> Bool = { false },
                               onPrefix: (TrackLoudnessProfileHandle) -> Void = { _ in }) -> Outcome {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let pass: TrackDecodePass
        switch TrackDecodePass.open(url, profile: profile, measureAt: engineRate) {
        case let .success(opened):
            pass = opened
        case let .failure(failure):
            return .failed(failure.reason)
        }
        defer { pass.profiler.map(asLoudnessProfilerDestroy) }
        let streamed = pass.stream(prefixSeconds: prefixSeconds, isCancelled: isCancelled, onPrefix: onPrefix)
        if streamed.cancelled {
            return .cancelled
        }
        if let error = streamed.error {
            return .failed(error)
        }
        guard let measurement = pass.measurement else { return .failed("nothing measured") }
        switch measurement.finish() {
        case let .success(analysis):
            let whole = pass.profiler.flatMap { TrackLoudnessProfileHandle(taking: asLoudnessProfilerFinishFull($0)) }
            return .analysed(TrackAnalysis(analysis, analyzer: measurement.analyzer, identity: identity,
                                           sourceRateHz: measurement.sourceRate, analysedAt: Date()),
                             profile: whole)
        case let .failure(failure):
            return .failed(failure.reason)
        }
    }
}
