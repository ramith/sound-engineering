// SRCQualityMeasure — headless measurement of Apple's AVAudioConverter(.max) SRC quality.
//
// B5 VERIFICATION TOOL, not production code. It REPLICATES the exact converter setup the Enhanced
// playback path (B4) uses — AVAudioConverter(from:to:), sampleRateConverterQuality = .max (default
// Normal algorithm), the pull convert(to:error:withInputFrom:) API with a once-latch input block
// and slack output capacity — but feeds it pure sine tones so we can MEASURE the imaging/aliasing
// it produces and validate the B4 choice with real dBFS numbers. Imports NOTHING from the
// AdaptiveSound app target; changes no production code. AVAudioConverter is a pure DSP object (no
// audio device), so this runs headless.
//
// Method: generate a full-scale sine at f in the SOURCE domain; convert to the DEST rate; window
// the converted output with a 4-term Blackman-Harris window and real-FFT it (vDSP); then, all from
// the SAME lobe-peak measure so the ratios are scale-consistent:
//   SIGNAL   = peak power of the tone's main lobe (calibrated so a clean full-scale tone ~ 0 dBFS).
//   IMAGING  = strongest image lobe (principal image at |sourceRate - f| folded into the dest band).
//   ALIASING = worst broadband spur, excluding the signal and image lobes (residual aliasing).
// Imaging/aliasing are reported RELATIVE TO THE TONE. Thresholds (pipeline plan): imaging < -60,
// aliasing < -80 dBFS. Both directions measured: 44100 -> 48000 (live up-conversion) and reverse.

import Accelerate
import AVFoundation
import Foundation

// MARK: - Constants

enum Measure {
    /// Source-domain length per tone (power of two). ~1.5 s @ 44.1 kHz — fine bin resolution + a
    /// fully settled resampler.
    static let sourceFrames = 65536

    /// FFT length over the converted output (power of two). ~1.5 Hz/bin @ 48 kHz — separates a
    /// signal lobe from its image and from broadband aliasing.
    static let fftSize = 32768

    /// Frames trimmed from the START of the converted output: the resampler polyphase warm-up
    /// transient is not steady-state and would smear the spectrum.
    static let outputWarmupTrim = 4096

    /// Extra frames added to the output buffer capacity beyond the estimated resampled frame count.
    /// This slack absorbs the polyphase interpolation tail the converter flushes at end-of-stream,
    /// matching the B4 makeInputBlock contract exactly.
    static let outputCapacitySlack: AVAudioFrameCount = 8192

    /// Main-lobe half-width (bins). The 4-term Blackman-Harris main lobe is ~8 bins wide.
    static let lobeHalfWidthBins = 8

    /// Guard radius (bins) excluded around the signal and image lobes when scanning for aliasing, so
    /// the window side-lobe skirt of the signal/image (< -92 dB) does not masquerade as aliasing.
    static let guardRadiusBins = 64

    /// Power floor so a perfectly clean spur reports a finite very-low dBFS, never -inf.
    static let powerFloor: Double = 1e-20

    /// Full-scale tone amplitude.
    static let toneAmplitude: Float = 1.0

    /// Thresholds (relative to the tone), from the pipeline plan.
    static let imagingThresholdDb: Double = -60.0
    static let aliasingThresholdDb: Double = -80.0

    /// Test tones (Hz), in the source domain.
    static let toneFrequencies: [Double] = [1000, 5000, 10000, 19000, 20000]

    /// Source and destination sample rates under test (Hz).
    static let rate44100: Double = 44100
    static let rate48000: Double = 48000

    /// Divisor for converting Hz to kHz in display strings.
    static let hzPerKHz: Double = 1000

    /// Margin (Hz) subtracted from the dest Nyquist when deciding whether to skip a tone. Tones
    /// within this margin of Nyquist have no stable signal bin and are skipped.
    static let nyquistGuardHz: Double = 100.0
}

// MARK: - Converter (replicates B4 exactly)

/// Build a stereo-float `AVAudioFormat` at `rate`. Non-interleaved (the AVAudioEngine standard
/// format), matching the file processingFormat / player outputFormat B4 converts between.
private func stereoFloatFormat(rate: Double) -> AVAudioFormat? {
    AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: rate,
        channels: 2,
        interleaved: false
    )
}

/// A stereo float input buffer of length `sourceSamples.count`, both channels filled identically.
private func makeInputBuffer(_ sourceSamples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frameCount = AVAudioFrameCount(sourceSamples.count)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
    }
    buffer.frameLength = frameCount
    if let channels = buffer.floatChannelData {
        for sample in 0 ..< sourceSamples.count {
            channels[0][sample] = sourceSamples[sample]
            channels[1][sample] = sourceSamples[sample]
        }
    }
    return buffer
}

/// Convert `sourceSamples` (replicated to both stereo channels) from `sourceRate` to `destRate`
/// through a converter configured EXACTLY like the B4 Enhanced resampler — `AVAudioConverter`,
/// `.max` quality (default Normal algorithm), and the pull `convert(to:error:withInputFrom:)` API
/// with a once-per-call input latch + slack output capacity. Returns the converted LEFT channel
/// (both are identical), incl. the resampler tail, or nil on a setup/conversion failure.
private func convertTone(
    sourceSamples: [Float],
    sourceRate: Double,
    destRate: Double
) -> [Float]? {
    guard
        let inputFormat = stereoFloatFormat(rate: sourceRate),
        let outputFormat = stereoFloatFormat(rate: destRate),
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
        let inputBuffer = makeInputBuffer(sourceSamples, format: inputFormat)
    else {
        return nil
    }
    converter.sampleRateConverterQuality = .max

    // Output capacity: input frames * rate ratio + slack for the interpolation tail (mirrors B4).
    let estimatedOut = Double(sourceSamples.count) * destRate / sourceRate
    let outCapacity = AVAudioFrameCount(estimatedOut.rounded(.up)) + Measure.outputCapacitySlack
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity)
    else {
        return nil
    }

    // Once-latch input block: hand the whole source over exactly once, then report end-of-stream so
    // the converter flushes its tail (identical contract to B4's makeInputBlock).
    var inputConsumed = false
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
        if inputConsumed {
            outStatus.pointee = .endOfStream
            return nil
        }
        inputConsumed = true
        outStatus.pointee = .haveData
        return inputBuffer
    }

    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
    if status == .error {
        if let conversionError {
            FileHandle.standardError.write(Data("convert error: \(conversionError)\n".utf8))
        }
        return nil
    }

    let producedFrames = Int(outputBuffer.frameLength)
    guard producedFrames > 0, let outChannels = outputBuffer.floatChannelData else {
        return nil
    }
    var result = [Float](repeating: 0, count: producedFrames)
    for sample in 0 ..< producedFrames {
        result[sample] = outChannels[0][sample]
    }
    return result
}

// MARK: - Per-tone measurement

private struct ToneResult {
    let frequency: Double
    let toneDb: Double // signal level (dBFS, ~0 for a full-scale tone)
    let imagingDb: Double // strongest image lobe relative to the tone
    let aliasingDb: Double // worst broadband passband spur relative to the tone
    let pass: Bool
}

/// FFT bins of the candidate SRC image locations for a sine at `frequency`: |k*sourceRate +- f|
/// (k = 1..3) folded into [0, destNyquist]. Excludes any candidate coinciding with the signal lobe.
private func imageBins(
    frequency: Double,
    sourceRate: Double,
    destRate: Double,
    signalBin: Int
) -> [Int] {
    let destNyquist = destRate / 2.0
    var bins: [Int] = []
    for harmonic in 1 ... 3 {
        let base = Double(harmonic) * sourceRate
        for sign in [-1.0, 1.0] {
            let raw = abs(base + sign * frequency)
            // Fold into [0, destNyquist] by mirroring about the dest rate / Nyquist.
            var folded = raw.truncatingRemainder(dividingBy: destRate)
            if folded > destNyquist { folded = destRate - folded }
            guard folded > 1.0, folded < destNyquist - 1.0 else { continue }
            let bin = binForFrequency(folded, rate: destRate, fftSize: Measure.fftSize)
            if abs(bin - signalBin) <= Measure.lobeHalfWidthBins { continue }
            bins.append(bin)
        }
    }
    return bins
}

/// Generate the full-scale source sine and convert it through the replicated B4 converter, then
/// return its windowed power spectrum (offset past the warm-up transient). Nil on any failure.
private func convertedSpectrum(
    frequency: Double,
    sourceRate: Double,
    destRate: Double
) -> [Double]? {
    var source = [Float](repeating: 0, count: Measure.sourceFrames)
    let omega = 2.0 * Double.pi * frequency / sourceRate
    for index in 0 ..< Measure.sourceFrames {
        source[index] = Measure.toneAmplitude * Float(sin(omega * Double(index)))
    }
    guard let converted = convertTone(
        sourceSamples: source, sourceRate: sourceRate, destRate: destRate
    ) else {
        return nil
    }
    guard converted.count >= Measure.outputWarmupTrim + Measure.fftSize else {
        FileHandle.standardError.write(Data("not enough converted output for f=\(frequency)\n".utf8))
        return nil
    }
    return powerSpectrum(converted, offset: Measure.outputWarmupTrim, fftSize: Measure.fftSize)
}

/// Measure one tone for a given conversion direction.
private func measureTone(
    frequency: Double,
    sourceRate: Double,
    destRate: Double
) -> ToneResult? {
    guard let power = convertedSpectrum(
        frequency: frequency, sourceRate: sourceRate, destRate: destRate
    ) else {
        return nil
    }

    // Signal lobe at `frequency` in the DEST domain.
    let signalBin = binForFrequency(frequency, rate: destRate, fftSize: Measure.fftSize)
    let signalPower = lobePeakPower(power, centerBin: signalBin)
    guard signalPower > 0, signalPower.isFinite else { return nil }

    // Imaging: strongest image lobe (the principal one is at |sourceRate - f| folded into band).
    let imgBins = imageBins(
        frequency: frequency, sourceRate: sourceRate, destRate: destRate, signalBin: signalBin
    )
    var imagingPower: Double = 0
    for bin in imgBins {
        imagingPower = max(imagingPower, lobePeakPower(power, centerBin: bin))
    }

    // Aliasing: worst spur across the passband, excluding guard zones around the signal and every
    // image lobe, so this isolates residual broadband aliasing distinct from the principal image.
    let aliasingPower = worstSpurPower(
        power,
        loBin: 1,
        hiBin: power.count - 1,
        excludeCenters: imgBins + [signalBin],
        excludeRadius: Measure.guardRadiusBins
    )

    // dBFS. lobePeakPower recovers the tone's amplitude^2 (coherent-gain-normalised), so a clean
    // full-scale (A=1) sine reads ~0 dBFS (minus small scalloping loss for off-bin tones) — a sanity
    // check on normalisation. Imaging/aliasing are RELATIVE TO THE TONE, from the same peak measure.
    let fullScaleRefPower = 1.0
    let toneDb = powerRatioToDb(signalPower / fullScaleRefPower)
    let imagingDb = powerRatioToDb(imagingPower / signalPower)
    let aliasingDb = powerRatioToDb(aliasingPower / signalPower)
    let pass = imagingDb < Measure.imagingThresholdDb && aliasingDb < Measure.aliasingThresholdDb

    return ToneResult(
        frequency: frequency,
        toneDb: toneDb,
        imagingDb: imagingDb,
        aliasingDb: aliasingDb,
        pass: pass
    )
}

// MARK: - Direction runner

private func formatDb(_ value: Double) -> String {
    String(format: "%7.2f dBFS", value)
}

/// Run all tones for one direction; print one line per tone; return true iff every tone passed.
private func runDirection(sourceRate: Double, destRate: Double) -> Bool {
    let srcK = Int(sourceRate / Measure.hzPerKHz)
    let dstK = Int(destRate / Measure.hzPerKHz)
    print("=== \(srcK)k -> \(dstK)k  (AVAudioConverter, sampleRateConverterQuality = .max) ===")
    var allPass = true
    for frequency in Measure.toneFrequencies {
        // Skip tones at or above the dest Nyquist (no stable signal bin).
        guard frequency < destRate / 2.0 - Measure.nyquistGuardHz else {
            print(String(
                format: "f=%6.0f Hz  SKIP (>= dest Nyquist %.0f Hz)",
                frequency, destRate / 2.0
            ))
            continue
        }
        guard let result = measureTone(
            frequency: frequency, sourceRate: sourceRate, destRate: destRate
        ) else {
            print(String(format: "f=%6.0f Hz  MEASURE FAILED", frequency))
            allPass = false
            continue
        }
        let verdict = result.pass ? "PASS" : "FAIL"
        print(String(
            format: "f=%6.0f Hz  tone=%@  imaging=%@  aliasing=%@  [%@]",
            result.frequency,
            formatDb(result.toneDb),
            formatDb(result.imagingDb),
            formatDb(result.aliasingDb),
            verdict
        ))
        if !result.pass { allPass = false }
    }
    return allPass
}

// MARK: - Main

print("SRCQualityMeasure — AVAudioConverter(.max) imaging/aliasing characterisation")
print(String(
    format: "Thresholds: imaging < %.0f dBFS, aliasing < %.0f dBFS (relative to the tone)",
    Measure.imagingThresholdDb, Measure.aliasingThresholdDb
))
print(String(
    format: "FFT=%d over converted output, source frames=%d, Blackman-Harris window, warmup trim=%d\n",
    Measure.fftSize, Measure.sourceFrames, Measure.outputWarmupTrim
))

let upPass = runDirection(sourceRate: Measure.rate44100, destRate: Measure.rate48000)
print("")
let downPass = runDirection(sourceRate: Measure.rate48000, destRate: Measure.rate44100)
print("")

if upPass, downPass {
    print("RESULT: ALL TONES PASS — Apple AVAudioConverter(.max) meets the B4 imaging/aliasing bar.")
    exit(0)
} else {
    print("RESULT: ONE OR MORE TONES FAILED — see [FAIL] lines above.")
    exit(1)
}
