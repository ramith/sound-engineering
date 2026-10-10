// VerifyEQReallocation.swift — Sprint EQ (EQ1b): a re-allocation keeps the EQ (engine-plan §6, B-5).
//
// ONE engine is re-formatted stereo @ 48 kHz -> 6ch @ 44.1 kHz -> stereo @ 48 kHz with the M2-c
// dance (`reconfigureAndRender`: stop -> reconnect -> re-enable manual rendering -> start). Each step
// re-allocates the AU's render resources, which re-initialises the kernel through
// `Realizer::reinitializeKernel`: the Realizer re-solves the EQ at the new rate and the EQ module
// snaps to it, so the curve never drops out or fades in from flat. The rate change is what makes
// the check bite: a curve designed for 48 kHz is never played at 44.1 kHz (the module holds flat
// instead), so a re-allocation that did not re-solve plays flat there and fails. The EQ and
// Intensity 0 (the EQ-only path: EQ -> limiter, no normaliser) are published ONCE, before the
// first start; the first allocation's dispatch_sync runs after those drains on the Realizer's
// serial queue, so the curve is in place for block one.
//
// At every step, each channel's tone (`syntheticToneHz`) must play at the gain the designer reads
// back for the curve at that rate (`asEqDesign`) within 0.1 dB, and a step at an earlier step's
// rate must play the same as it within 0.1 dB (engine-plan §10). The -12 dBFS tones plus at most
// +6 dB stay below the safety limiter.

@preconcurrency import AVFAudio
import AVFoundation
import Foundation

/// A jagged ±6 dB curve, so neighbouring probe tones sit on different gains.
private let eqReallocCurve: [Float] = (0 ..< 31).map { Float($0 % 5 - 2) * 3 }

/// Engine-plan §10: the played response is unchanged within 0.1 dB.
private let eqReallocToleranceDb = 0.1

/// Where the measurement starts: past the bells' settle (the module snaps; the bells ring out).
private let eqReallocSettleFrames = 9600

/// The probe tones are all multiples of 250 Hz.
private let eqReallocToneSpacingHz = 250

/// The steady-state window at `rate`: from the settle point, the longest span holding a whole
/// number of cycles of every probe tone, so the single-bin estimate has no leakage.
private func wholeCycleWindow(rate: Double) -> Range<Int> {
    let fs = Int(rate)
    var (lhs, rhs) = (fs, eqReallocToneSpacingHz)
    while rhs != 0 {
        (lhs, rhs) = (rhs, lhs % rhs)
    }
    let period = fs / lhs // samples per whole cycle of the tone spacing
    let span = (Int(totalFrames) - eqReallocSettleFrames) / period * period
    return eqReallocSettleFrames ..< eqReallocSettleFrames + span
}

/// The played dB at each of `hz` for `points` at `rate`, read back from the designer.
private func designedResponseDb(points: [Float], hz: [Double], rate: Double) -> [Float]? {
    guard let designer = asEqDesignerCreate() else { return nil }
    defer { asEqDesignerDestroy(designer) }
    var centres = [Float](repeating: 0, count: points.count)
    var response = [Float](repeating: 0, count: hz.count)
    let designed = centres.withUnsafeMutableBufferPointer { centreBuffer in
        response.withUnsafeMutableBufferPointer { responseBuffer in
            hz.withUnsafeBufferPointer { hzBuffer in
                var output = AsEqDesignOutput(centreDb: centreBuffer.baseAddress,
                                              responseHz: hzBuffer.baseAddress,
                                              responseDb: responseBuffer.baseAddress,
                                              responseCount: UInt32(hz.count),
                                              filterGainDb: nil, svfK: nil, svfM1: nil)
                return asEqDesign(designer, points, UInt32(points.count), rate, &output)
            }
        }
    }
    return designed ? response : nil
}

/// The level of the `hz` tone in `samples` (rendered at `rate`), relative to the input tone, in dB
/// (one DFT bin by quadrature over the whole-cycle window).
private func toneGainDb(_ samples: [Float], hz: Double, rate: Double) -> Double {
    let window = wholeCycleWindow(rate: rate)
    var inPhase = 0.0
    var quadrature = 0.0
    for n in window {
        let phase = 2.0 * Double.pi * hz * Double(n) / rate
        inPhase += Double(samples[n]) * cos(phase)
        quadrature += Double(samples[n]) * sin(phase)
    }
    let amplitude = 2.0 * (inPhase * inPhase + quadrature * quadrature).squareRoot() / Double(window.count)
    return 20.0 * log10(amplitude / Double(toneAmplitude))
}

/// One step's verdict: every channel's tone within tolerance of the design at `rate` and of
/// `reference` (an earlier step at the same rate, for the channels both have). Prints the
/// PASS/FAIL line; returns the measured gains on PASS.
private func checkPlayedEQ(_ captured: [[Float]], rate: Double, reference: [Double]?, label: String) -> [Double]? {
    let hz = captured.indices.map { syntheticToneHz(channel: $0) }
    guard let expected = designedResponseDb(points: eqReallocCurve, hz: hz, rate: rate) else {
        print("EQ1b FAIL \(label): asEqDesign rejected the curve at \(rate) Hz")
        return nil
    }
    let measured = zip(captured, hz).map { toneGainDb($0, hz: $1, rate: rate) }
    let designError = zip(measured, expected).map { abs($0 - Double($1)) }.max() ?? .infinity
    let drift = zip(measured, reference ?? measured).map { abs($0 - $1) }.max() ?? .infinity
    let measuredText = measured.map { String(format: "%+.3f", $0) }.joined(separator: ", ")
    let expectedText = expected.map { String(format: "%+.3f", $0) }.joined(separator: ", ")
    // `!(x <= tolerance)` so a NaN measurement fails too.
    if !(designError <= eqReallocToleranceDb) {
        print("EQ1b FAIL \(label): played [\(measuredText)] dB vs designed [\(expectedText)] dB "
            + "(worst \(String(format: "%.3f", designError)) dB > \(eqReallocToleranceDb) dB) — the EQ was lost")
        return nil
    }
    if !(drift <= eqReallocToleranceDb) {
        print("EQ1b FAIL \(label): played [\(measuredText)] dB drifted \(String(format: "%.3f", drift)) dB "
            + "from the earlier step at \(rate) Hz (> \(eqReallocToleranceDb) dB)")
        return nil
    }
    print("EQ1b PASS \(label): played [\(measuredText)] dB = designed [\(expectedText)] dB "
        + "(worst \(String(format: "%.3f", designError)) dB, drift \(String(format: "%.3f", drift)) dB)")
    return measured
}

/// Drive one engine through stereo @ 48 k -> 6ch @ 44.1 k -> stereo @ 48 k with an EQ published
/// once, and assert at every step that the EQ still plays as designed. True only if all pass.
func verifyEQReallocation() -> Bool {
    print("--- EQ1b re-allocation: stereo@48k -> 6ch@44.1k -> stereo@48k keeps the EQ (one engine) ---")
    guard let unit = instantiateAU() else {
        print("EQ1b FAIL: AU instantiate returned nil")
        return false
    }
    let handle = Unmanaged.passUnretained(unit.auAudioUnit).toOpaque()
    publishIntensity(handle, 0)
    guard publishEQ(handle, eqReallocCurve, UInt32(eqReallocCurve.count), true) else {
        print("EQ1b FAIL: publishEQ rejected the curve")
        return false
    }
    let graph = ReconfigurableGraph.make(unit: unit)
    defer { graph.engine.stop() }

    var references: [Double: [Double]] = [:]
    let steps: [(channels: AVAudioChannelCount, rate: Double)] = [(2, 48000), (6, 44100), (2, 48000)]
    for step in steps {
        let label = "[EQ realloc->\(step.channels)ch@\(Int(step.rate))]"
        guard let captured = reconfigureAndRender(graph, channelCount: step.channels, rate: step.rate,
                                                  check: "EQ1b"),
            let measured = checkPlayedEQ(captured, rate: step.rate, reference: references[step.rate],
                                         label: label)
        else {
            return false
        }
        let designRate = eqDesignSampleRate(handle)
        if designRate != step.rate {
            print("EQ1b FAIL \(label): the Realizer designs at \(designRate) Hz, not \(step.rate)")
            return false
        }
        references[step.rate] = references[step.rate] ?? measured
    }
    print("EQ1b PASS: the EQ played as designed through every re-allocation")
    return true
}
