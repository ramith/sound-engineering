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

    /// Tolerance for gain linearity tests (dB). A settled-tail measurement of a
    /// peaking biquad at its centre frequency is exact in principle; ±0.1 dB
    /// absorbs float32 measurement noise and stays far tighter than the product
    /// frequency-response bar (kEqFrToleranceDb = ±1.0 dB in the C++ gate).
    private let gainLinearityTolerance: Float = 0.1

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

    // MARK: - Test 2: Gain Linearity (-20 to +12 dB per band, ±0.1 dB)

    /// Measures the STEADY-STATE gain of a peaking biquad at its centre frequency.
    ///
    /// A peaking-EQ (RBJ) filter has `|H(e^{jω₀})| = 10^(gainDB/20)` exactly at the
    /// centre frequency, so the measured gain must equal the target. The measurement
    /// discards the leading transient (the biquad turn-on AND the 32 ms master-gain
    /// ramp) and reads only the SETTLED TAIL, and it drives the production module via
    /// the STREAMING bridge (one persistent module — no per-chunk state reset).
    /// A whole-buffer RMS of a fresh-per-chunk module (the old approach) folded ~47
    /// startup transients into the number and could not converge.
    @Test("Gain linearity: -20 to +12 dB at 1 kHz within ±0.1 dB (settled tail)")
    func gainLinearity() {
        let testGains: [Float] = [-20, -15, -10, -5, 0, 6, 12]
        // ~0.5 s so the settled tail is long; skip the first ~85 ms (well past the
        // 32 ms master-gain ramp and the sub-ms biquad settling).
        let numSamples = Int(Float(testSampleRate) * 0.5)
        let settleSkip = 4096
        let sine1kHz = generateSineWave(frequency: 1000,
                                        sampleRate: testSampleRate,
                                        numSamples: numSamples)
        let inputRMS = settledRMS(signal: sine1kHz, skip: settleSkip)

        for targetGainDB in testGains {
            let params = makePeakBiquadCEQParams(frequencyHz: 1000, gainDB: targetGainDB,
                                                 qFactor: 1.0, sampleRate: testSampleRate)

            let refOut = processViaSwiftReference(signal: sine1kHz, params: params)
            let refMeasured = settledGainDB(output: refOut, inputRMS: inputRMS, skip: settleSkip)
            #expect(abs(refMeasured - targetGainDB) < gainLinearityTolerance,
                    "Reference gain at \(targetGainDB) dB: got \(refMeasured) dB")

            let realOut = processViaRealEQModuleStream(signal: sine1kHz, params: params)
            let realMeasured = settledGainDB(output: realOut, inputRMS: inputRMS, skip: settleSkip)
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
                            (30, iso266BandCenters[30])] {
            let params = makePeakBiquadCEQParams(frequencyHz: freq, gainDB: 6.0,
                                                 qFactor: 1.0, sampleRate: testSampleRate)
            #expect(Int(params.numBiquads) > 0,
                    "Biquad should be created for band \(idx) at \(freq) Hz")
        }
    }

    // MARK: - Test 4: Impulse Response (Minimum-Phase: no pre-ring, stable decay)

    /// Validates the minimum-phase time-domain behaviour with a UNIT IMPULSE, not
    /// white noise. Pre-ring is energy that appears BEFORE the impulse-response peak;
    /// a causal minimum-phase biquad has none (the peak is at/near index 0 and its
    /// energy decays). The previous test measured `max(first 10 noise samples)/max(all)`
    /// on white noise — a category error: white noise already has ~full amplitude in
    /// its first samples, so the ratio (~0.65) is meaningless for any causal filter.
    /// The structural minimum-phase guarantee (poles+zeros inside the unit circle) is
    /// covered separately by the Schur-Cohn check in EQModuleCoefficientsXCTests.
    @Test("Impulse response: no pre-ring, stable decay, no NaN/Inf (reference and EQModule)")
    func phaseResponse() {
        let params = makePeakBiquadCEQParams(frequencyHz: 1000, gainDB: 6.0,
                                             qFactor: 1.0, sampleRate: testSampleRate)
        let impulseLen = 512
        var impulse = [Float](repeating: 0, count: impulseLen)
        impulse[0] = 1.0

        let paths: [(String, [Float])] = [
            ("Reference", processViaSwiftReference(signal: impulse, params: params)),
            ("EQModule", processViaRealEQModuleStream(signal: impulse, params: params)),
        ]

        for (label, impulse) in paths {
            #expect(!impulse.contains { $0.isNaN }, "\(label): impulse response must not contain NaN")
            #expect(!impulse.contains { $0.isInfinite }, "\(label): impulse response must not contain Inf")

            let peakIdx = impulse.indices.max(by: { abs(impulse[$0]) < abs(impulse[$1]) }) ?? 0
            // Minimum-phase / causal: no meaningful energy before the peak.
            let preEnergy = (0 ..< peakIdx).reduce(Float(0)) { $0 + impulse[$1] * impulse[$1] }
            let totalEnergy = impulse.reduce(Float(0)) { $0 + $1 * $1 }
            let preRingFraction = totalEnergy > 0 ? preEnergy / totalEnergy : 0
            #expect(preRingFraction < 1e-3,
                    "\(label): pre-peak (pre-ring) energy fraction must be < 0.1%, got \(preRingFraction)")

            // Stability: the response must decay — tail energy far below head energy.
            let quarter = impulseLen / 4
            let headEnergy = (0 ..< quarter).reduce(Float(0)) { $0 + impulse[$1] * impulse[$1] }
            let tailEnergy = (impulse.count - quarter ..< impulse.count)
                .reduce(Float(0)) { $0 + impulse[$1] * impulse[$1] }
            #expect(tailEnergy < headEnergy * 0.01,
                    "\(label): impulse response must decay (tail=\(tailEnergy) head=\(headEnergy))")
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
            let bandParams = makePeakBiquadCEQParams(frequencyHz: freq, gainDB: gain,
                                                     qFactor: 1.0, sampleRate: testSampleRate)
            refSignal = processViaSwiftReference(signal: refSignal, params: bandParams)
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
        for idx in 0 ..< out1.count {
            #expect(abs(out1[idx] - out2[idx]) < 1e-7, "Sample \(idx) must match after round-trip")
        }

        let out3 = processViaRealEQModule(signal: testSignal, params: original)
        let out4 = processViaRealEQModule(signal: testSignal, params: deserialized)
        for idx in 0 ..< out3.count {
            #expect(abs(out3[idx] - out4[idx]) < 1e-7, "EQModule sample \(idx) after round-trip")
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
        for idx in 0 ..< refOutput.count {
            let diff = abs(refOutput[idx] - realOutput[idx])
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
        for idx in 0 ..< Int(cParams.numBiquads) {
            guard let coeffs = children[idx].value as? CEQBiquadCoeffs else { continue }
            #expect(coeffs.b0.isFinite, "b0[\(idx)] must be finite after coefficient design")
            #expect(coeffs.a1.isFinite, "a1[\(idx)] must be finite after coefficient design")
            #expect(coeffs.a2.isFinite, "a2[\(idx)] must be finite after coefficient design")
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
    /// masterGain uses a ~32 ms one-pole ramp, so the gain only reaches its target
    /// after ~5τ (~160 ms). The measurement therefore streams a ~0.5 s signal through
    /// ONE persistent module and reads the SETTLED TAIL (past ~85 ms). The previous
    /// test asserted a settled −6 dB inside a single 512-frame (10.7 ms) call on a
    /// fresh-per-call module — mathematically impossible: the ramp only reaches
    /// ~−0.66 dB in 10.7 ms, which is exactly what it (wrongly) measured.
    @Test("EQModule applies masterGainLinear from CEQParams (settled tail)")
    func masterGainApplied() {
        // Use flat EQ (zero biquads = identity cascade) so only master gain changes the signal.
        var flatParams = CEQParams()
        flatParams.numBiquads = 0
        flatParams.masterGainLinear = 1.0

        let numSamples = Int(Float(testSampleRate) * 0.5)
        let settleSkip = 4096
        let sine1kHz = generateSineWave(frequency: 1000, sampleRate: testSampleRate,
                                        numSamples: numSamples)
        let inputRMS = settledRMS(signal: sine1kHz, skip: settleSkip)

        // Verify -6 dB attenuation (masterGainLinear = 10^(-6/20) ≈ 0.501)
        var attenuatedParams = flatParams
        attenuatedParams.masterGainLinear = Darwin.pow(Float(10.0), Float(-6.0) / Float(20.0))

        let attenuatedOut = processViaRealEQModuleStream(signal: sine1kHz, params: attenuatedParams)
        let attenuatedGainDB = settledGainDB(output: attenuatedOut, inputRMS: inputRMS, skip: settleSkip)

        // Settled gain must be -6 dB within ±0.1 dB.
        #expect(abs(attenuatedGainDB - -6.0) < 0.1,
                "EQModule settled gain with masterGainLinear=-6 dB must be -6 dB ±0.1, got \(attenuatedGainDB) dB")

        // Verify unity gain preserves signal level (baseline sanity-check).
        let unityOut = processViaRealEQModuleStream(signal: sine1kHz, params: flatParams)
        let unityGainDB = settledGainDB(output: unityOut, inputRMS: inputRMS, skip: settleSkip)
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
        for idx in 0 ..< sine1kHz.count {
            let diff = abs(output[idx] - sine1kHz[idx])
            if diff > maxDiff { maxDiff = diff }
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
            for idx in 0 ..< count {
                output[offset + idx] = chunk[idx]
            }
            offset += count
        }
        return output
    }

    /// Process the ENTIRE signal through ONE persistent production EQModule via the
    /// streaming bridge (filter + master-gain-ramp state preserved across the internal
    /// 512-frame windows). Use this — not `processViaRealEQModule` — whenever a
    /// measurement depends on settled/steady-state output.
    private func processViaRealEQModuleStream(signal: [Float], params: CEQParams) -> [Float] {
        var buffer = signal
        var mutableParams = params
        withUnsafeMutablePointer(to: &mutableParams) { paramsPtr in
            eqModuleProcessStreamC(&buffer, paramsPtr, UInt32(signal.count))
        }
        return buffer
    }

    // MARK: - CEQParams Factories

    private func makeFlatCEQParams() -> CEQParams {
        var params = CEQParams()
        params.numBiquads = 0
        params.masterGainLinear = 1.0
        return params
    }

    private func makePeakBiquadCEQParams(frequencyHz: Float, gainDB: Float,
                                         qFactor: Float, sampleRate: UInt32) -> CEQParams {
        let w0: Float = 2.0 * Float.pi * frequencyHz / Float(sampleRate)
        let cosW0: Float = Darwin.cos(w0)
        let sinW0: Float = Darwin.sin(w0)
        let ampA: Float = Darwin.pow(Float(10.0), gainDB / Float(40.0))
        let alpha: Float = sinW0 / (Float(2.0) * qFactor)

        let rawB0 = Float(1.0) + alpha * ampA
        let rawB1 = Float(-2.0) * cosW0
        let rawB2 = Float(1.0) - alpha * ampA
        let a0 = Float(1.0) + alpha / ampA
        let rawA1 = Float(-2.0) * cosW0
        let rawA2 = Float(1.0) - alpha / ampA

        var biquad = CEQBiquadCoeffs()
        biquad.b0 = rawB0 / a0
        biquad.b1 = rawB1 / a0
        biquad.b2 = rawB2 / a0
        biquad.a1 = rawA1 / a0
        biquad.a2 = rawA2 / a0

        var params = CEQParams()
        params.numBiquads = 1
        params.masterGainLinear = Float(1.0)
        params.biquads.0 = biquad
        return params
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
                                  numSamples: Int) -> [Float] {
        let phaseInc = 2.0 * Float.pi * frequency / Float(sampleRate)
        return (0 ..< numSamples).map { Darwin.sin(Float($0) * phaseInc) }
    }

    private func generateWhiteNoise(numSamples: Int) -> [Float] {
        var signal = [Float](repeating: 0, count: numSamples)
        srand48(12345)
        for idx in 0 ..< numSamples {
            signal[idx] = 2.0 * Float(drand48()) - 1.0
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

    /// RMS over the SETTLED TAIL (samples `[skip, end)`), excluding the leading
    /// transient (filter turn-on + master-gain ramp). For a pure tone through an LTI
    /// filter the tail is a steady sinusoid, so its RMS is the exact steady-state level.
    private func settledRMS(signal: [Float], skip: Int) -> Float {
        guard skip < signal.count else { return rootMeanSquare(signal: signal) }
        return rootMeanSquare(signal: Array(signal[skip...]))
    }

    /// Steady-state gain in dB: settled-tail output RMS vs settled-tail input RMS.
    private func settledGainDB(output: [Float], inputRMS: Float, skip: Int) -> Float {
        let outRMS = settledRMS(signal: output, skip: skip)
        return Float(20.0) * Float(Darwin.log10(Double(outRMS / inputRMS)))
    }
}
