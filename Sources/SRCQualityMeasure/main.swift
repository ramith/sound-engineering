// SRCQualityMeasure — the Enhanced path's sample-rate conversion, measured and GATED (`make gate`).
//
// Council C-26 / R-6 (R1.1-A, US-R1F-11). The old tool replicated the converter instead of running
// it, measured only imaging, and printed "tone −7.23 dBFS @ 20 kHz … [PASS]": it could not fail. This
// one drives the PRODUCTION converter — AudioFormatKit's `StreamingResampler`, which the app's
// resampler runs, in the same 8192-frame chunks — with pure tones, and checks every rate pair the
// app converts against the bar:
//
//   passband  |gain| ≤ 0.1 dB for tones up to 20 kHz (below 44.1 kHz, up to the same fraction of the
//             narrower rate's Nyquist);
//   stopband  every image and alias ≤ −100 dB re the tone (out-of-band tones up to the source's
//             Nyquist for a down-conversion; the images of the passband tones for every pair);
//   identity  bit-exact when the rates are equal;
//   speed     the converter streams ≥ 2× faster than real time on any core (its own CPU time, stereo).
//             The resampler converts the next chunk while about two primed chunks still play, so
//             0.5× is the hard floor and 2× a fourfold margin; measured on an M4 Pro: 14–114× on a
//             performance core, 6–52× on an efficiency core (`taskpolicy -b`), the slowest being
//             384 kHz → 48 kHz.
//
// Then a CONTROL runs the same checks on the converter the app shipped before R1.1 (the Normal
// algorithm, everything else the same). It must FAIL both the passband and the stopband check, or
// this gate is blind and fails itself. Exit 0 only when production passes and the control fails.
//
// Method: each tone is converted in production chunks; the first `warmupFrames` of output are
// skipped; over the next `windowFrames` a Blackman-Harris-weighted least-squares fit reads the
// tone's level at its exact frequency (no FFT bin, so no scalloping), the fitted tone is removed,
// and every image / alias frequency (k·fs_in ± f, folded into the output band) is read the same way
// on the residual. Headless: AVAudioConverter is a pure DSP object; no device, nothing played.

import Accelerate
import AudioFormatKit
@preconcurrency import AVFAudio
import Foundation

// MARK: - The bar

enum Bar {
    static let passbandToleranceDb = 0.1
    static let stopbandCeilingDb = -100.0
    static let minimumRealTimeFactor = 2.0
    /// The passband edge at 44.1 kHz and above; narrower rates keep the same fraction of Nyquist.
    static let passbandEdgeHz = 20000.0
    static let referenceRate = 44100.0
}

enum Measure {
    static let amplitude = 0.5 // −6 dBFS: no clipping from the filters' overshoot
    static let warmupFrames = 8192 // output frames skipped: the filter filling
    static let windowFrames = 32768 // output frames fitted
    static let channels: AVAudioChannelCount = 2 // stereo, as the app streams it
    static let imageOrders = 1 ... 4 // k in k·fs_in ± f
    /// A component this close to the wanted tone can't be told apart from it (it shows as gain).
    static let separationHz = 50.0
    /// Fits this close to 0 Hz or to Nyquist are ill-conditioned over the window.
    static let edgeGuardHz = 20.0
}

/// Every conversion the app makes: each file rate → the 48 kHz graph, and 48 kHz → the common device
/// rates (the device boundary the Engine sprint runs through the same converter).
let graphRate = 48000.0
let fileRates: [Double] = [44100, 88200, 96000, 176_400, 192_000, 352_800, 384_000, 32000, 22050]
let deviceRates: [Double] = [44100, 88200, 96000, 176_400, 192_000]
let conversions: [(from: Double, to: Double)] =
    fileRates.map { ($0, graphRate) } + deviceRates.map { (graphRate, $0) }
let identities: [Double] = [44100, 48000, 96000]

// MARK: - Streaming through the production converter

/// One tone streamed through the converter.
struct ToneRun {
    /// The converted left channel.
    let output: [Double]
    /// This thread's CPU time inside `convert`.
    let cpuSeconds: Double
    /// The seconds of input converted.
    let inputSeconds: Double
}

/// Stream a tone at `frequency` (`fromRate`) through a `StreamingResampler` in production chunks
/// until `frames` output frames exist; nil on a failure.
func streamTone(frequency: Double, from fromRate: Double, to toRate: Double, algorithm: String,
                frames: Int) -> ToneRun? {
    guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: fromRate, channels: Measure.channels),
          let outFormat = AVAudioFormat(standardFormatWithSampleRate: toRate, channels: Measure.channels),
          let resampler = StreamingResampler(from: inFormat, to: outFormat, algorithm: algorithm),
          let chunk = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: StreamingResampler.inputChunkFrames)
    else { return nil }
    let chunkFrames = Int(StreamingResampler.inputChunkFrames)
    let omega = 2 * Double.pi * frequency / fromRate
    var output: [Double] = []
    output.reserveCapacity(frames + chunkFrames * 8)
    var tone = [Double](repeating: 0, count: chunkFrames)
    var cpu = 0.0
    var consumed = 0
    while output.count < frames {
        var start = omega * Double(consumed)
        var step = omega
        vDSP_vrampD(&start, &step, &tone, 1, vDSP_Length(chunkFrames))
        var count = Int32(chunkFrames)
        vvsin(&tone, tone, &count)
        guard let channels = chunk.floatChannelData else { return nil }
        var gain = Measure.amplitude
        vDSP_vsmulD(tone, 1, &gain, &tone, 1, vDSP_Length(chunkFrames))
        vDSP_vdpsp(tone, 1, channels[0], 1, vDSP_Length(chunkFrames))
        for channel in 1 ..< Int(Measure.channels) {
            channels[channel].update(from: channels[0], count: chunkFrames)
        }
        chunk.frameLength = AVAudioFrameCount(chunkFrames)
        consumed += chunkFrames
        let before = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        guard let converted = try? resampler.convert(chunk, inputEnded: false) else { return nil }
        cpu += Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - before) / 1e9
        guard let left = converted.buffer.floatChannelData?[0] else { return nil }
        let length = Int(converted.buffer.frameLength)
        var widened = [Double](repeating: 0, count: length)
        vDSP_vspdp(left, 1, &widened, 1, vDSP_Length(length))
        output += widened
    }
    return ToneRun(output: output, cpuSeconds: cpu, inputSeconds: Double(consumed) / fromRate)
}

// MARK: - Weighted least-squares tone reading

/// The 4-term Blackman-Harris window over the fitted span: its side lobes (≤ −92 dB, falling away)
/// keep one component's leakage out of another's reading.
let window: [Double] = (0 ..< Measure.windowFrames).map { index in
    let phase = 2 * Double.pi * Double(index) / Double(Measure.windowFrames - 1)
    return 0.35875 - 0.48829 * cos(phase) + 0.14128 * cos(2 * phase) - 0.01168 * cos(3 * phase)
}

/// A sinusoid fitted to a signal: its amplitude, and the fitted wave itself (to remove it).
struct ToneFit {
    let amplitude: Double
    let wave: [Double]
}

/// The sinusoid at `frequency` (`rate`) that best fits `signal` under the window (weighted least
/// squares on a sine and a cosine at the exact frequency: no FFT bin, so no scalloping).
func fitTone(_ signal: [Double], frequency: Double, rate: Double) -> ToneFit {
    let count = signal.count
    var ramp = [Double](repeating: 0, count: count)
    var start = 0.0
    var step = 2 * Double.pi * frequency / rate
    vDSP_vrampD(&start, &step, &ramp, 1, vDSP_Length(count))
    var sine = [Double](repeating: 0, count: count)
    var cosine = [Double](repeating: 0, count: count)
    var length = Int32(count)
    vvsincos(&sine, &cosine, ramp, &length)
    let weightedSine = vDSP.multiply(window, sine)
    let weightedCosine = vDSP.multiply(window, cosine)
    let sumSS = vDSP.dot(weightedSine, sine)
    let sumCC = vDSP.dot(weightedCosine, cosine)
    let sumSC = vDSP.dot(weightedSine, cosine)
    let sumXS = vDSP.dot(weightedSine, signal)
    let sumXC = vDSP.dot(weightedCosine, signal)
    let determinant = sumSS * sumCC - sumSC * sumSC
    let partA = (sumXS * sumCC - sumXC * sumSC) / determinant
    let partB = (sumXC * sumSS - sumXS * sumSC) / determinant
    return ToneFit(amplitude: (partA * partA + partB * partB).squareRoot(),
                   wave: vDSP.add(vDSP.multiply(partA, sine), vDSP.multiply(partB, cosine)))
}

func decibels(_ ratio: Double) -> Double {
    20 * log10(max(ratio, 1e-15))
}

/// `frequency` folded into the band of a signal sampled at `rate` (0 … rate/2).
func fold(_ frequency: Double, into rate: Double) -> Double {
    abs(frequency - rate * (frequency / rate).rounded())
}

// MARK: - One conversion

struct Verdict {
    var passbandWorstDb = 0.0 // the largest |gain| in the passband
    var stopbandWorstDb = -400.0 // the strongest image / alias
    var stopbandWorstAt = ""
    var cpuSeconds = 0.0
    var inputSeconds = 0.0
    var failure: String?

    var passbandPass: Bool {
        failure == nil && passbandWorstDb <= Bar.passbandToleranceDb
    }

    var stopbandPass: Bool {
        failure == nil && stopbandWorstDb <= Bar.stopbandCeilingDb
    }

    var realTimeFactor: Double {
        cpuSeconds > 0 ? inputSeconds / cpuSeconds : .infinity
    }
}

/// The tones for one conversion.
struct TonePlan {
    /// The passband's top: 20 kHz at 44.1 kHz and above; the same fraction of the narrower rate below.
    let edge: Double
    /// Tones up to the edge, which must come through level.
    let passband: [Double]
    /// For a down-conversion: tones from just above the output's Nyquist to just below the source's,
    /// which must not come through at all.
    let stopband: [Double]

    init(from fromRate: Double, to toRate: Double) {
        edge = min(Bar.passbandEdgeHz, Bar.passbandEdgeHz / Bar.referenceRate * min(fromRate, toRate))
        passband = [1000.0, 5000, 10000, 15000, 18000, 19000, 20000].map { [edge] in $0 / Bar.passbandEdgeHz * edge }
        let low = toRate / 2 + 500
        let high = fromRate / 2 * 0.98
        stopband = fromRate > toRate ? (0 ..< 5).map { low + (high - low) * Double($0) / 4 } : []
    }
}

func measure(from fromRate: Double, to toRate: Double, algorithm: String) -> Verdict {
    var verdict = Verdict()
    let plan = TonePlan(from: fromRate, to: toRate)
    for frequency in plan.passband + plan.stopband {
        guard let run = streamTone(frequency: frequency, from: fromRate, to: toRate, algorithm: algorithm,
                                   frames: Measure.warmupFrames + Measure.windowFrames)
        else {
            verdict.failure = "conversion failed at \(Int(frequency)) Hz"
            return verdict
        }
        verdict.cpuSeconds += run.cpuSeconds
        verdict.inputSeconds += run.inputSeconds
        var residual = Array(run.output[Measure.warmupFrames ..< Measure.warmupFrames + Measure.windowFrames])
        let wanted = frequency <= plan.edge
        if wanted {
            // The wanted tone: its level, then removed so its leakage can't read as an image.
            let fit = fitTone(residual, frequency: frequency, rate: toRate)
            verdict.passbandWorstDb = max(verdict.passbandWorstDb, abs(decibels(fit.amplitude / Measure.amplitude)))
            residual = vDSP.subtract(residual, fit.wave)
        }
        // Everything that must not be there: the tone itself when it lies above the output's band
        // (k = 0), and its images k·fs_in ± f — each folded into the output band.
        var components: [Double] = frequency > toRate / 2 ? [fold(frequency, into: toRate)] : []
        for order in Measure.imageOrders {
            components += [Double(order) * fromRate - frequency, Double(order) * fromRate + frequency]
                .map { fold($0, into: toRate) }
        }
        for component in components
            where component > Measure.edgeGuardHz && component < toRate / 2 - Measure.edgeGuardHz
            && !(wanted && abs(component - frequency) < Measure.separationHz) {
            let level = decibels(fitTone(residual, frequency: component, rate: toRate).amplitude / Measure.amplitude)
            if level > verdict.stopbandWorstDb {
                verdict.stopbandWorstDb = level
                verdict.stopbandWorstAt = "\(Int(frequency)) Hz → \(Int(component)) Hz"
            }
        }
    }
    return verdict
}

/// Equal rates: noise through the production chunks (and the final flush) must come back bit for bit.
func identityIsBitExact(rate: Double) -> Bool {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: Measure.channels),
          let resampler = StreamingResampler(from: format, to: format),
          let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: StreamingResampler.inputChunkFrames)
    else { return false }
    let chunkFrames = Int(StreamingResampler.inputChunkFrames)
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    var input: [Float] = []
    var output: [Float] = []
    for index in 0 ... 8 {
        let last = index == 8
        chunk.frameLength = last ? 0 : AVAudioFrameCount(chunkFrames)
        guard let channels = chunk.floatChannelData else { return false }
        for frame in 0 ..< Int(chunk.frameLength) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let sample = Float(Double(state >> 40) / Double(1 << 24) - 0.5)
            for channel in 0 ..< Int(Measure.channels) {
                channels[channel][frame] = sample
            }
            input.append(sample)
        }
        guard let converted = try? resampler.convert(chunk, inputEnded: last),
              let left = converted.buffer.floatChannelData?[0] else { return false }
        output += UnsafeBufferPointer(start: left, count: Int(converted.buffer.frameLength))
    }
    return input == output
}

// MARK: - Report

func kilohertz(_ rate: Double) -> String {
    String(format: "%gk", rate / 1000)
}

func report(_ verdict: Verdict, from fromRate: Double, to toRate: Double, speed: Bool) -> String {
    let pair = "\(kilohertz(fromRate)) → \(kilohertz(toRate))".padding(toLength: 16, withPad: " ", startingAt: 0)
    if let failure = verdict.failure {
        return "  \(pair) FAIL — \(failure)"
    }
    let edge = TonePlan(from: fromRate, to: toRate).edge
    var line = "  \(pair)"
        + String(format: "passband %.4f dB (to %.1f kHz) %@   ", verdict.passbandWorstDb, edge / 1000,
                 verdict.passbandPass ? "PASS" : "FAIL")
        + String(format: "stopband %7.1f dB (%@) %@", verdict.stopbandWorstDb, verdict.stopbandWorstAt,
                 verdict.stopbandPass ? "PASS" : "FAIL")
    if speed {
        let share = verdict.cpuSeconds / verdict.inputSeconds * 100
        line += String(format: "   CPU %.2f %% of a core (%.0f× real time) %@", share, verdict.realTimeFactor,
                       verdict.realTimeFactor >= Bar.minimumRealTimeFactor ? "PASS" : "FAIL")
    }
    return line
}

// MARK: - Main

let algorithmName = StreamingResampler.algorithm.replacingOccurrences(of: "AVSampleRateConverterAlgorithm_", with: "")
print("SRC gate — AudioFormatKit.StreamingResampler (Apple AVAudioConverter, \(algorithmName), max quality),")
print("production chunks of \(StreamingResampler.inputChunkFrames) frames, stereo")
print(String(format: "Bar: passband |gain| ≤ %.1f dB to %.0f kHz · images and aliases ≤ %.0f dB · "
        + "equal rates bit-exact · ≥ %.0f× real time\n", Bar.passbandToleranceDb, Bar.passbandEdgeHz / 1000,
    Bar.stopbandCeilingDb, Bar.minimumRealTimeFactor))

/// The production converter on every conversion and equal rate. True when all of it meets the bar.
func productionMeetsTheBar() -> Bool {
    var passes = true
    for conversion in conversions {
        let verdict = measure(from: conversion.from, to: conversion.to, algorithm: StreamingResampler.algorithm)
        print(report(verdict, from: conversion.from, to: conversion.to, speed: true))
        passes = passes && verdict.passbandPass && verdict.stopbandPass
            && verdict.realTimeFactor >= Bar.minimumRealTimeFactor
    }
    for rate in identities {
        let exact = identityIsBitExact(rate: rate)
        print("  \("\(kilohertz(rate)) → \(kilohertz(rate))".padding(toLength: 16, withPad: " ", startingAt: 0))"
            + "equal rates: \(exact ? "bit-exact PASS" : "NOT bit-exact FAIL")")
        passes = passes && exact
    }
    return passes
}

/// The control: the pre-R1.1 converter (Normal) on every conversion. True when it fails both the
/// passband and the stopband somewhere — i.e. when this gate can tell.
func controlFailsTheBar() -> Bool {
    print("\nCONTROL — the converter before R1.1 (the Normal algorithm) must FAIL this bar:")
    var passbandFailures = 0
    var stopbandFailures = 0
    for conversion in conversions {
        let verdict = measure(from: conversion.from, to: conversion.to,
                              algorithm: AVSampleRateConverterAlgorithm_Normal)
        print(report(verdict, from: conversion.from, to: conversion.to, speed: false))
        passbandFailures += verdict.passbandPass ? 0 : 1
        stopbandFailures += verdict.stopbandPass ? 0 : 1
    }
    let fails = passbandFailures > 0 && stopbandFailures > 0
    print("  the control fails the passband on \(passbandFailures) and the stopband on "
        + "\(stopbandFailures) of \(conversions.count) conversions"
        + (fails ? "" : " — the gate cannot tell a bad converter from a good one"))
    return fails
}

let productionPasses = productionMeetsTheBar()
let controlFails = controlFailsTheBar()
if productionPasses, controlFails {
    print("\nRESULT: PASS — the Enhanced converter meets the bar on every conversion, and the gate can fail.")
    exit(0)
}

print("\nRESULT: FAIL — "
    + (productionPasses ? "the control passed: this gate is blind." : "see the FAIL lines above."))
exit(1)
