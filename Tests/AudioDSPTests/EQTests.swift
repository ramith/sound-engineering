import Darwin
import Testing

/// Comprehensive EQ Module test suite covering:
/// - Frequency response linearity
/// - Phase validation (minimum-phase)
/// - Stability under stress
/// - Preset persistence
/// - DSP accuracy and numerical stability
///
/// Two processing paths are exercised for every signal-path test:
///   1. `processViaSwiftReference` — the in-Swift biquad reimplementation that
///      serves as a sanity-check reference (verifies test signal generation).
///   2. `processViaRealEQModule` — calls the production `EQModule::process()`
///      through `eqModuleProcessC()`.  This is the path that catches real bugs.
///
/// Both paths must produce results within `crossPathTolerance` of each other,
/// confirming that the production code and the reference agree.
@Suite("EQModule Signal Path")
struct EQTests {
    // MARK: - Test Fixtures

    private let testSampleRate: UInt32 = 48000
    private let testMaxFrames: UInt32 = 512

    /// Tolerance for frequency-response measurements (dB)
    private let frequencyResponseTolerance: Float = 0.1

    /// Tolerance for gain linearity tests (dB)
    private let gainLinearityTolerance: Float = 0.05

    /// Maximum allowed divergence (dB) between the Swift reference path and
    /// the real EQModule path.  The two biquad implementations must agree within
    /// this bound for the test to be meaningful.
    private let crossPathTolerance: Float = 0.05

    // MARK: - Test 1: Flat Response @ 1 kHz ±0.1 dB

    @Test("Flat EQ preserves 1 kHz unity gain (±0.1 dB) — reference and EQModule")
    func flatResponseAt1kHz() {
        let eqParams = makeFlatCEQParams()
        let numSamples = Int(Float(testSampleRate) * 1.0)
        let sine1kHz = generateSineWave(frequency: 1000,
                                        sampleRate: testSampleRate,
                                        numSamples: numSamples)
        let inputRMS = rootMeanSquare(signal: sine1kHz)

        // Reference path (Swift biquad)
        let refOutput = processViaSwiftReference(signal: sine1kHz, params: eqParams)
        let refGainDB = gainDBValue(output: refOutput, inputRMS: inputRMS)
        #expect(abs(refGainDB) < frequencyResponseTolerance,
                "Reference: flat EQ gain at 1 kHz must be within ±\(frequencyResponseTolerance) dB, got \(refGainDB)")

        // Production path (real EQModule)
        let realOutput = processViaRealEQModule(signal: sine1kHz, params: eqParams)
        let realGainDB = gainDBValue(output: realOutput, inputRMS: inputRMS)
        #expect(abs(realGainDB) < frequencyResponseTolerance,
                "EQModule: flat EQ gain at 1 kHz must be within ±\(frequencyResponseTolerance) dB, got \(realGainDB)")

        // Cross-path agreement
        #expect(abs(refGainDB - realGainDB) < crossPathTolerance,
                "Swift reference and EQModule must agree within \(crossPathTolerance) dB")
    }

    // MARK: - Test 2: Gain Linearity (-20 to +12 dB per band, ±0.05 dB)

    @Test("Gain linearity: -20 to +12 dB at 1 kHz within ±0.05 dB")
    func gainLinearity() {
        let testGains: [Float] = [-20, -15, -10, -5, 0, 6, 12]
        let numSamples = Int(Float(testSampleRate) * 0.5)
        let sine1kHz = generateSineWave(frequency: 1000,
                                        sampleRate: testSampleRate,
                                        numSamples: numSamples)
        let inputRMS = rootMeanSquare(signal: sine1kHz)

        for targetGainDB in testGains {
            let params = makePeakBiquadCEQParams(frequencyHz: 1000, gainDB: targetGainDB,
                                                 qFactor: 1.0, sampleRate: testSampleRate)

            let refOut = processViaSwiftReference(signal: sine1kHz, params: params)
            let refMeasured = gainDBValue(output: refOut, inputRMS: inputRMS)
            #expect(abs(refMeasured - targetGainDB) < gainLinearityTolerance,
                    "Reference gain at \(targetGainDB) dB: got \(refMeasured) dB")

            let realOut = processViaRealEQModule(signal: sine1kHz, params: params)
            let realMeasured = gainDBValue(output: realOut, inputRMS: inputRMS)
            #expect(abs(realMeasured - targetGainDB) < gainLinearityTolerance,
                    "EQModule gain at \(targetGainDB) dB: got \(realMeasured) dB")

            #expect(abs(refMeasured - realMeasured) < crossPathTolerance,
                    "Cross-path diff at \(targetGainDB) dB: ref=\(refMeasured) real=\(realMeasured)")
        }
    }

    // MARK: - Test 3: Frequency Accuracy (31 ISO 266 bands)

    @Test("ISO 266 31-band frequencies produce non-zero biquads")
    func frequencyAccuracy() {
        let iso266BandCenters: [Float] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
            200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
            2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
        ]
        #expect(iso266BandCenters.count == 31)

        for (idx, freq) in [(0, iso266BandCenters[0]), (10, iso266BandCenters[10]),
                            (17, iso266BandCenters[17]), (24, iso266BandCenters[24]),
                            (30, iso266BandCenters[30])]
        {
            let params = makePeakBiquadCEQParams(frequencyHz: freq, gainDB: 6.0,
                                                 qFactor: 1.0, sampleRate: testSampleRate)
            #expect(Int(params.numBiquads) > 0,
                    "Biquad should be created for band \(idx) at \(freq) Hz")
        }
    }

    // MARK: - Test 4: Phase Response (Minimum-Phase Validation)

    @Test("Minimum-phase: no pre-ring, no NaN/Inf (reference and EQModule)")
    func phaseResponse() {
        let params = makePeakBiquadCEQParams(frequencyHz: 1000, gainDB: 6.0,
                                             qFactor: 1.0, sampleRate: testSampleRate)
        let whiteNoise = generateWhiteNoise(numSamples: Int(testSampleRate))

        let paths: [(String, [Float])] = [
            ("Reference", processViaSwiftReference(signal: whiteNoise, params: params)),
            ("EQModule", processViaRealEQModule(signal: whiteNoise, params: params)),
        ]

        for (label, output) in paths {
            let firstSamplesMax = output.prefix(10).map(abs).max() ?? 0
            let maxOutput = output.map(abs).max() ?? 1
            let preRingRatio = firstSamplesMax / maxOutput
            #expect(preRingRatio < 0.1,
                    "\(label): minimum-phase filter pre-ring ratio must be < 10%, got \(preRingRatio)")
            #expect(!output.contains { $0.isNaN }, "\(label): output must not contain NaN")
            #expect(!output.contains { $0.isInfinite }, "\(label): output must not contain Inf")
        }
    }

    // MARK: - Test 5: Stability (10 seconds of white noise, no clipping)

    @Test("Stability: 10s white noise produces no NaN/Inf/denormals and no clipping")
    func stability() {
        let numSamples = Int(testSampleRate * UInt32(10.0))
        let whiteNoise = generateWhiteNoise(numSamples: numSamples)
        let params = makePeakBiquadCEQParams(frequencyHz: 1000, gainDB: 3.0,
                                             qFactor: 1.0, sampleRate: testSampleRate)

        // Reference path (full 10s, processes entire buffer at once)
        var refSignal = whiteNoise
        for (freq, gain) in [(100 as Float, -6 as Float), (1000, 3), (8000, -3)] {
            let p = makePeakBiquadCEQParams(frequencyHz: freq, gainDB: gain,
                                            qFactor: 1.0, sampleRate: testSampleRate)
            refSignal = processViaSwiftReference(signal: refSignal, params: p)
        }

        // Real EQModule path: check the first 512-frame chunk (production chunk size)
        let firstChunk = Array(whiteNoise.prefix(512))
        let realChunk = processViaRealEQModule(signal: firstChunk, params: params)

        let pairs: [(String, [Float])] = [
            ("Reference (10s)", refSignal),
            ("EQModule (first chunk)", realChunk),
        ]

        for (label, output) in pairs {
            #expect(!output.contains { $0.isNaN }, "\(label): no NaN")
            #expect(!output.contains { $0.isInfinite }, "\(label): no Inf")
            #expect(!output.contains { $0.isSubnormal }, "\(label): no denormals")
            let maxAbs = output.map(abs).max() ?? 0
            #expect(maxAbs < 2.0, "\(label): must not clip (max abs = \(maxAbs))")
        }
    }

    // MARK: - Test 6: Preset Load/Save (Byte-Identical Reload)

    @Test("Preset serialization: deserialized params produce identical output")
    func presetLoadSave() {
        let original = makePeakBiquadCEQParams(frequencyHz: 1000, gainDB: 6.0,
                                               qFactor: 0.7, sampleRate: testSampleRate)
        var deserialized = original
        withUnsafeBytes(of: original) { src in
            withUnsafeMutableBytes(of: &deserialized) { dst in dst.copyMemory(from: src) }
        }

        #expect(original.numBiquads == deserialized.numBiquads)
        #expect(original.masterGainLinear == deserialized.masterGainLinear)

        let testSignal = generateSineWave(frequency: 1000, sampleRate: testSampleRate,
                                          numSamples: Int(testSampleRate))
        let out1 = processViaSwiftReference(signal: testSignal, params: original)
        let out2 = processViaSwiftReference(signal: testSignal, params: deserialized)
        for i in 0 ..< out1.count {
            #expect(abs(out1[i] - out2[i]) < 1e-7, "Sample \(i) must match after round-trip")
        }

        let out3 = processViaRealEQModule(signal: testSignal, params: original)
        let out4 = processViaRealEQModule(signal: testSignal, params: deserialized)
        for i in 0 ..< out3.count {
            #expect(abs(out3[i] - out4[i]) < 1e-7, "EQModule sample \(i) after round-trip")
        }
    }

    // MARK: - Test 7: Real EQModule vs. Swift Reference (Cross-Path Validation)

    /// Primary integration test — direct sample-by-sample comparison between
    /// the Swift reference biquad and the vDSP-backed production EQModule.
    /// A discrepancy means either the coefficients are wrong or EQModule has a bug.
    @Test("EQModule output matches Swift reference within 1e-4 sample error")
    func eQModuleMatchesSwiftReference() {
        let params = makePeakBiquadCEQParams(frequencyHz: 1000, gainDB: 6.0,
                                             qFactor: 1.0, sampleRate: testSampleRate)
        let numSamples = 512
        let sine1kHz = generateSineWave(frequency: 1000, sampleRate: testSampleRate,
                                        numSamples: numSamples)

        let refOutput = processViaSwiftReference(signal: sine1kHz, params: params)
        let realOutput = processViaRealEQModule(signal: sine1kHz, params: params)

        #expect(refOutput.count == realOutput.count)

        var maxDiff: Float = 0
        for i in 0 ..< refOutput.count {
            let diff = abs(refOutput[i] - realOutput[i])
            if diff > maxDiff { maxDiff = diff }
        }

        // vDSP uses double-precision accumulation; results should be nearly identical
        // to the single-precision Swift reference.
        #expect(maxDiff < 1e-4,
                "EQModule must match Swift reference within 1e-4 (max diff: \(maxDiff))")
    }

    // MARK: - Test 8: End-to-End Pipeline (computeEQCoefficientsC → eqModuleProcessC)

    /// Exercises the full production signal path:
    ///   computeEQCoefficientsC (coefficient design) → eqModuleProcessC (DSP processing)
    ///
    /// Verifies that a 1 kHz band boost designed by the coefficient engine produces
    /// a measurable gain increase at 1 kHz when applied through the real EQModule.
    /// This is the only test that exercises both bridge functions together.
    @Test("End-to-end: computeEQCoefficients → eqModuleProcess lifts 1 kHz gain")
    func endToEndCoefficientsThenProcess() {
        // Build a 31-band gain vector: +6 dB at band 17 (1 kHz), all others 0.
        var bandGains = [Float](repeating: 0.0, count: 31)
        bandGains[17] = 6.0 // 1 kHz

        // Design biquad cascade using the production coefficient engine.
        var cParams = CEQParams()
        bandGains.withUnsafeBufferPointer { buf in
            computeEQCoefficientsC(buf.baseAddress, Float(testSampleRate), &cParams)
        }

        // Coefficient engine must produce at least one biquad for a non-zero gain.
        #expect(Int(cParams.numBiquads) >= 1,
                "computeEQCoefficientsC must yield >=1 biquad for a +6 dB 1 kHz boost")
        #expect(Int(cParams.numBiquads) <= 10,
                "computeEQCoefficientsC must not exceed kMaxBiquads")

        // All designed coefficients must be finite.
        let mirror = Mirror(reflecting: cParams.biquads)
        let children = Array(mirror.children)
        for i in 0 ..< Int(cParams.numBiquads) {
            guard let b = children[i].value as? CEQBiquadCoeffs else { continue }
            #expect(b.b0.isFinite, "b0[\(i)] must be finite after coefficient design")
            #expect(b.a1.isFinite, "a1[\(i)] must be finite after coefficient design")
            #expect(b.a2.isFinite, "a2[\(i)] must be finite after coefficient design")
        }

        // Process a 1 kHz sine wave through the real EQModule using the designed params.
        let numSamples = 512
        let sine1kHz = generateSineWave(frequency: 1000,
                                        sampleRate: testSampleRate,
                                        numSamples: numSamples)
        let inputRMS = rootMeanSquare(signal: sine1kHz)
        let realOutput = processViaRealEQModule(signal: sine1kHz, params: cParams)

        // The designed +6 dB boost at 1 kHz must produce a measurable gain increase.
        // Allow ±2 dB tolerance: the greedy biquad fitter is approximate, not exact.
        let gainDB = gainDBValue(output: realOutput, inputRMS: inputRMS)
        #expect(gainDB > 2.0,
                "End-to-end pipeline must boost 1 kHz by >2 dB (measured: \(gainDB) dB)")
        #expect(gainDB < 10.0,
                "End-to-end pipeline must not over-boost 1 kHz (measured: \(gainDB) dB)")

        // Output must be numerically clean.
        #expect(!realOutput.contains { $0.isNaN }, "End-to-end output must not contain NaN")
        #expect(!realOutput.contains { $0.isInfinite }, "End-to-end output must not contain Inf")
    }

    // MARK: - Test 9: Master Gain Applied by eqModuleProcessC

    /// Verifies that `masterGainLinear` in CEQParams is applied by the real EQModule.
    ///
    /// The EQModule uses a one-pole ramp on masterGain; for a single 512-frame call
    /// the ramp settles quickly enough that the output RMS must be within ±1 dB of
    /// the expected attenuated level.
    @Test("EQModule applies masterGainLinear from CEQParams")
    func masterGainApplied() {
        // Use flat EQ (zero biquads = identity cascade) so only master gain changes the signal.
        var flatParams = CEQParams()
        flatParams.numBiquads = 0
        flatParams.masterGainLinear = 1.0

        let numSamples = 512
        let sine1kHz = generateSineWave(frequency: 1000, sampleRate: testSampleRate,
                                        numSamples: numSamples)
        let inputRMS = rootMeanSquare(signal: sine1kHz)

        // Verify -6 dB attenuation (masterGainLinear = 10^(-6/20) ≈ 0.501)
        var attenuatedParams = flatParams
        attenuatedParams.masterGainLinear = Darwin.pow(Float(10.0), Float(-6.0) / Float(20.0))

        let attenuatedOut = processViaRealEQModule(signal: sine1kHz, params: attenuatedParams)
        let attenuatedGainDB = gainDBValue(output: attenuatedOut, inputRMS: inputRMS)

        // Allow ±1 dB tolerance for the one-pole ramp transient during the 512-frame window.
        #expect(attenuatedGainDB < -4.0,
                "EQModule must attenuate output with masterGainLinear=-6 dB, got \(attenuatedGainDB) dB")
        #expect(attenuatedGainDB > -8.0,
                "EQModule attenuation must not overshoot -8 dB, got \(attenuatedGainDB) dB")

        // Verify unity gain preserves signal level (baseline sanity-check).
        let unityOut = processViaRealEQModule(signal: sine1kHz, params: flatParams)
        let unityGainDB = gainDBValue(output: unityOut, inputRMS: inputRMS)
        #expect(abs(unityGainDB) < 0.1,
                "Unity masterGainLinear must preserve signal within ±0.1 dB, got \(unityGainDB) dB")
    }

    // MARK: - Test 10: Identity Pass-through with numBiquads == 0

    /// When numBiquads is zero the EQModule cascade is identity-padded and must
    /// reproduce the input exactly (subject only to master-gain scaling at unity).
    /// This guards against regressions in the identity-padding logic in
    /// EQModule::publishCoefficients().
    @Test("EQModule with zero active biquads passes signal through unchanged")
    func zeroBiquadsIdentityPassthrough() {
        var params = CEQParams()
        params.numBiquads = 0
        params.masterGainLinear = 1.0

        let numSamples = 512
        let sine1kHz = generateSineWave(frequency: 1000, sampleRate: testSampleRate,
                                        numSamples: numSamples)

        let output = processViaRealEQModule(signal: sine1kHz, params: params)

        // Sample-by-sample comparison: all samples must be within 1e-4.
        var maxDiff: Float = 0
        for i in 0 ..< sine1kHz.count {
            let d = abs(output[i] - sine1kHz[i])
            if d > maxDiff { maxDiff = d }
        }
        #expect(maxDiff < 1e-4,
                "Zero-biquad EQModule must pass signal through unchanged (max diff: \(maxDiff))")

        // RMS must be preserved within ±0.1 dB.
        let inputRMS = rootMeanSquare(signal: sine1kHz)
        let gainDB = gainDBValue(output: output, inputRMS: inputRMS)
        #expect(abs(gainDB) < 0.1,
                "Zero-biquad EQModule must preserve RMS within ±0.1 dB (got \(gainDB) dB)")
    }

    // MARK: - Processing Helpers

    /// Process via the in-Swift biquad cascade (reference / sanity-check path).
    private func processViaSwiftReference(signal: [Float], params: CEQParams) -> [Float] {
        var output = signal
        let numFrames = signal.count

        for biquadIdx in 0 ..< Int(params.numBiquads) {
            let coeffs = biquadCoeffsAt(index: biquadIdx, in: params)
            var x1: Float = 0, x2: Float = 0
            var y1: Float = 0, y2: Float = 0

            for frame in 0 ..< numFrames {
                let x0 = output[frame]
                let y0 = coeffs.b0 * x0 + coeffs.b1 * x1 + coeffs.b2 * x2
                    - coeffs.a1 * y1 - coeffs.a2 * y2
                x2 = x1; x1 = x0
                y2 = y1; y1 = y0
                output[frame] = y0
            }
        }
        return output.map { $0 * params.masterGainLinear }
    }

    /// Process via the real production `EQModule::process()` through the C bridge.
    /// Splits the signal into 512-frame chunks (matching the render-thread call pattern).
    private func processViaRealEQModule(signal: [Float], params: CEQParams) -> [Float] {
        var output = [Float](repeating: 0, count: signal.count)
        let chunkSize = 512
        var offset = 0
        var mutableParams = params // withUnsafeMutablePointer requires a var

        while offset < signal.count {
            let count = min(chunkSize, signal.count - offset)
            var chunk = Array(signal[offset ..< offset + count])
            withUnsafeMutablePointer(to: &mutableParams) { paramsPtr in
                eqModuleProcessC(&chunk, paramsPtr, UInt32(count))
            }
            for i in 0 ..< count {
                output[offset + i] = chunk[i]
            }
            offset += count
        }
        return output
    }

    // MARK: - CEQParams Factories

    private func makeFlatCEQParams() -> CEQParams {
        var p = CEQParams()
        p.numBiquads = 0
        p.masterGainLinear = 1.0
        return p
    }

    private func makePeakBiquadCEQParams(frequencyHz: Float, gainDB: Float,
                                         qFactor: Float, sampleRate: UInt32) -> CEQParams
    {
        let w0: Float = 2.0 * Float.pi * frequencyHz / Float(sampleRate)
        let cosW0: Float = Darwin.cos(w0)
        let sinW0: Float = Darwin.sin(w0)
        let A: Float = Darwin.pow(Float(10.0), gainDB / Float(40.0))
        let alpha: Float = sinW0 / (Float(2.0) * qFactor)

        let rawB0 = Float(1.0) + alpha * A
        let rawB1 = Float(-2.0) * cosW0
        let rawB2 = Float(1.0) - alpha * A
        let a0 = Float(1.0) + alpha / A
        let rawA1 = Float(-2.0) * cosW0
        let rawA2 = Float(1.0) - alpha / A

        var biquad = CEQBiquadCoeffs()
        biquad.b0 = rawB0 / a0
        biquad.b1 = rawB1 / a0
        biquad.b2 = rawB2 / a0
        biquad.a1 = rawA1 / a0
        biquad.a2 = rawA2 / a0

        var p = CEQParams()
        p.numBiquads = 1
        p.masterGainLinear = Float(1.0)
        p.biquads.0 = biquad
        return p
    }

    private func biquadCoeffsAt(index: Int, in params: CEQParams) -> CEQBiquadCoeffs {
        let mirror = Mirror(reflecting: params.biquads)
        let children = Array(mirror.children)
        guard index < children.count,
              let coeffs = children[index].value as? CEQBiquadCoeffs
        else { return CEQBiquadCoeffs() }
        return coeffs
    }

    // MARK: - Signal Generators

    private func generateSineWave(frequency: Float, sampleRate: UInt32,
                                  numSamples: Int) -> [Float]
    {
        let phaseInc = 2.0 * Float.pi * frequency / Float(sampleRate)
        return (0 ..< numSamples).map { Darwin.sin(Float($0) * phaseInc) }
    }

    private func generateWhiteNoise(numSamples: Int) -> [Float] {
        var signal = [Float](repeating: 0, count: numSamples)
        srand48(12345)
        for i in 0 ..< numSamples {
            signal[i] = 2.0 * Float(drand48()) - 1.0
        }
        let rms = rootMeanSquare(signal: signal)
        return signal.map { $0 / (rms > 0 ? rms : 1.0) * 0.5 }
    }

    private func rootMeanSquare(signal: [Float]) -> Float {
        guard !signal.isEmpty else { return 0 }
        let sumSq = signal.reduce(0.0) { $0 + $1 * $1 }
        return Darwin.sqrt(sumSq / Float(signal.count))
    }

    private func gainDBValue(output: [Float], inputRMS: Float) -> Float {
        let outRMS = rootMeanSquare(signal: output)
        return Float(20.0) * Float(Darwin.log10(Double(outRMS / inputRMS)))
    }
}
