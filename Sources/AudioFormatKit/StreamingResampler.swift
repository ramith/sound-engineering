import AVFoundation
import Foundation

// MARK: - The Enhanced path's sample-rate converter (council C-26, KI-SND-02; R1.1-A)

/// Apple's `AVAudioConverter` at its **Mastering** algorithm and maximum quality, fed in the fixed
/// chunks the Enhanced resampler streams to the player. The ONE place the Enhanced path's conversion
/// is configured: the app's resampler (`EnhancedResampleSession`, the start and the gapless seam
/// alike) and the `make gate` SRC check (`SRCQualityMeasure`) run this exact code, so the gate
/// measures what plays.
///
/// **Why Mastering.** Measured through this code by `SRCQualityMeasure` on every conversion the app
/// makes: flat to 20 kHz (error under 0.0001 dB), every image and alias at −148 dB or below,
/// bit-exact when the rates are equal, and no time offset (the output lines up with the input's
/// timeline, so the playhead and the seams don't move). It costs about 0.9–3.5 % of one core for
/// stereo at 44.1–192 kHz (29–114× real time), about 7 % at 352.8 / 384 kHz (14×).
/// The Normal algorithm it replaces lost 8.25 dB at 20 kHz (44.1 → 48 kHz) and let a 192 → 48 kHz
/// alias through at −21 dB. It had been chosen on the belief that Mastering "would stall live
/// playback", which was never measured and is false: the first chunk holds back about 13 ms, the
/// end flushes it, and the totals are exact.
///
/// One instance per stream, used from one serial queue (its owner's): not thread-safe.
public final class StreamingResampler {
    /// Input frames per `convert` call — the Enhanced resampler's chunk (~186 ms at 44.1 kHz).
    public static let inputChunkFrames: AVAudioFrameCount = 8192

    /// Output frames allocated beyond a chunk's converted length, for the frames the converter holds
    /// back and flushes at the end, so the last chunk is never cut short.
    public static let outputSlackFrames: AVAudioFrameCount = 4096

    /// The algorithm the Enhanced path plays through.
    public static let algorithm = AVSampleRateConverterAlgorithm_Mastering

    /// The source's format (its rate, N-channel float) — what `convert` takes.
    public let inputFormat: AVAudioFormat

    /// The player's format (the graph's rate, N-channel float) — what `convert` returns.
    public let outputFormat: AVAudioFormat

    private let converter: AVAudioConverter

    /// `nil` when Apple has no converter between the two formats. `algorithm` is the production one
    /// unless overridden — which only the SRC gate does, with the old Normal, to prove it can fail.
    public init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat,
                 algorithm: String = StreamingResampler.algorithm) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        converter.sampleRateConverterAlgorithm = algorithm
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        self.converter = converter
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
    }

    /// One converted chunk.
    public struct Chunk {
        /// The converted frames (possibly none, while the converter fills its filter).
        public let buffer: AVAudioPCMBuffer
        /// The converter has flushed everything: no output follows.
        public let endOfStream: Bool
    }

    /// Why a chunk could not be converted.
    public enum Failure: Error {
        /// The output buffer could not be allocated.
        case outputAllocation
        /// The converter failed without saying why.
        case conversion
    }

    /// Convert one chunk of input (up to `inputChunkFrames` frames). The converter keeps its state
    /// across calls, so consecutive chunks join seamlessly. `inputEnded`: no input follows this chunk
    /// (an empty chunk with `inputEnded` just flushes) — the converter then outputs the frames it
    /// held back, and reports the end once it has.
    public func convert(_ input: AVAudioPCMBuffer, inputEnded: Bool) throws -> Chunk {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let inputFrames = max(input.frameLength, Self.inputChunkFrames)
        let capacity = AVAudioFrameCount((Double(inputFrames) * ratio).rounded(.up)) + Self.outputSlackFrames
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw Failure.outputAllocation
        }
        let feed = OneShotInput(buffer: input, ended: inputEnded)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            feed.next(outStatus)
        }
        switch status {
        case .error:
            throw error ?? Failure.conversion
        case .endOfStream:
            return Chunk(buffer: output, endOfStream: true)
        case .haveData, .inputRanDry:
            return Chunk(buffer: output, endOfStream: false)
        @unknown default:
            return Chunk(buffer: output, endOfStream: false)
        }
    }
}

/// Hands the converter one chunk exactly once per `convert` call; after that, "no data now" — or the
/// end of the stream, so it flushes. `@unchecked Sendable`: the converter calls the input block
/// synchronously, on the caller's thread, inside `convert` — one writer, no concurrency.
private final class OneShotInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let ended: Bool
    private var handedOver = false

    init(buffer: AVAudioPCMBuffer, ended: Bool) {
        self.buffer = buffer
        self.ended = ended
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !handedOver, buffer.frameLength > 0 else {
            status.pointee = ended ? .endOfStream : .noDataNow
            return nil
        }
        handedOver = true
        status.pointee = .haveData
        return buffer
    }
}
