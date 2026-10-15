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
/// **One stream across a same-format join** (council C-22, KI-GAP-04). The next track of the same
/// format feeds the SAME converter (`canContinue(with:)`): its frames follow the last track's, so the
/// filter's history spans the join and the two convert exactly as one input would. A converter per
/// track borders each with silence instead — a click at every join (13–27 dB below the peak, ±240
/// frames). `inputFrames` / `outputFrames` and `outputFrame(atInputFrame:)` place the join in the
/// output.
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

    /// Input frames the converter has taken since the stream began (every track it carried).
    public private(set) var inputFrames: Int64 = 0

    /// Output frames it has returned since the stream began.
    public private(set) var outputFrames: Int64 = 0

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

    // MARK: - The stream's timeline

    /// Whether input of `format` can go on through this stream: the same rate, channel count and
    /// layout as its input. A track of another format needs its own converter.
    public func canContinue(with format: AVAudioFormat) -> Bool {
        format == inputFormat
    }

    /// Where input frame `inputFrame` (counted from the stream's start) begins in the output: the
    /// first output frame at or after its time. The output lines up with the input's timeline —
    /// output frame j sits at input time j × inRate / outRate, with no offset (measured: ≤ 0.001
    /// frame on every rate pair the app converts) — so this is ⌈inputFrame × outRate / inRate⌉,
    /// exact in integers (44.1 → 48 kHz is 147 : 160).
    public func outputFrame(atInputFrame inputFrame: Int64) -> Int64 {
        let (inRate, outRate) = (inputFormat.sampleRate, outputFormat.sampleRate)
        guard inRate == inRate.rounded(), outRate == outRate.rounded(), inRate >= 1, outRate >= 1 else {
            return Int64((Double(inputFrame) * outRate / inRate).rounded(.up))
        }
        let divisor = Self.greatestCommonDivisor(Int64(inRate), Int64(outRate))
        let (numerator, denominator) = (Int64(outRate) / divisor, Int64(inRate) / divisor)
        let (quotient, remainder) = inputFrame.quotientAndRemainder(dividingBy: denominator)
        return quotient * numerator + (remainder * numerator + denominator - 1) / denominator
    }

    private static func greatestCommonDivisor(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var (larger, smaller) = (lhs, rhs)
        while smaller != 0 {
            (larger, smaller) = (smaller, larger % smaller)
        }
        return larger
    }

    // MARK: - Converting

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
    /// across calls, so consecutive chunks join seamlessly — the next track's too, when it has the
    /// same format. `inputEnded`: no input follows this chunk
    /// (an empty chunk with `inputEnded` just flushes) — the converter then outputs the frames it
    /// held back, and reports the end once it has.
    public func convert(_ input: AVAudioPCMBuffer, inputEnded: Bool) throws -> Chunk {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let chunkFrames = max(input.frameLength, Self.inputChunkFrames)
        let capacity = AVAudioFrameCount((Double(chunkFrames) * ratio).rounded(.up)) + Self.outputSlackFrames
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw Failure.outputAllocation
        }
        let feed = OneShotInput(buffer: input, ended: inputEnded)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            feed.next(outStatus)
        }
        if feed.handedOver {
            inputFrames += Int64(input.frameLength)
        }
        outputFrames += Int64(output.frameLength)
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
    /// The converter took the chunk.
    private(set) var handedOver = false

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
