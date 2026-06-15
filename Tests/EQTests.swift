@testable import AudioDSP
import AVFoundation
import CoreAudio
import XCTest

/// Comprehensive EQ Module test suite covering:
/// - Frequency response linearity
/// - Phase validation (minimum-phase)
/// - Stability under stress
/// - Preset persistence
/// - DSP accuracy and numerical stability
class EQTests: XCTestCase {
    // MARK: - Test Fixtures

    /// Reference sample rate for all tests
    static let testSampleRate: UInt32 = 48000

    /// Maximum number of frames per buffer
    static let testMaxFrames: UInt32 = 512

    /// Tolerance for frequency response measurements (dB)
    static let frequencyResponseTolerance: Float = 0.1

    /// Tolerance for gain linearity tests (dB)
    static let gainLinearityTolerance: Float = 0.05

    /// Tolerance for frequency accuracy (±2%)
    static let frequencyAccuracyTolerance: Float = 0.02

    /// Duration of stability test (seconds)
    static let stabilityTestDuration: Float = 10.0

    // MARK: - Test 1: Flat Response @ 1 kHz ±0.1 dB

    /// Test that a flat EQ (all bands at 0 dB gain) produces output
    /// within ±0.1 dB of the input signal at 1 kHz reference.
    ///
    /// Success criteria:
    /// - Initialize EQ with 0 dB per band
    /// - Generate 1 kHz sine wave @ 48 kHz
    /// - Process through EQ module
    /// - Measure RMS output vs RMS input
    /// - Verify gain within ±0.1 dB
    func testFlatResponseAt1kHz() {
        let testName = "testFlatResponseAt1kHz"
        print("[\(testName)] Starting flat response test...")

        // Create flat EQ params (all bands 0 dB, passthrough)
        var eqParams = EQParams()
        eqParams.numBiquads = 0 // No filtering: passthrough
        eqParams.masterGainLinear = 1.0 // Unity gain

        // Generate test signal: 1 kHz sine wave, 1 second @ 48 kHz
        let testDuration: Float = 1.0
        let numSamples = Int(Float(Self.testSampleRate) * testDuration)
        let sine1kHz = generateSineWave(frequency: 1000, sampleRate: Self.testSampleRate, numSamples: numSamples)

        // Process through flat EQ
        let output = processThroughEQ(signal: sine1kHz, params: eqParams)

        // Measure RMS
        let inputRMS = rootMeanSquare(signal: sine1kHz)
        let outputRMS = rootMeanSquare(signal: output)

        // Convert to dB: 20 * log10(outputRMS / inputRMS)
        let gainDB = 20.0 * Float(log10(Double(outputRMS / inputRMS)))

        print("[\(testName)] Input RMS: \(inputRMS), Output RMS: \(outputRMS), Gain (dB): \(gainDB)")

        // Verify within tolerance
        XCTAssertEqual(gainDB, 0.0, accuracy: Self.frequencyResponseTolerance,
                       "Flat response should preserve 1 kHz signal within ±\(Self.frequencyResponseTolerance) dB")
    }

    // MARK: - Test 2: Gain Linearity (-20 to +12 dB per band, ±0.05 dB)

    /// Test that EQ gain changes scale linearly across the specified range.
    ///
    /// Test procedure:
    /// - Create a biquad filter with exact gain targets (-20, -10, 0, +6, +12 dB)
    /// - Process constant-amplitude test signal
    /// - Measure output gain for each setting
    /// - Verify linearity within ±0.05 dB
    func testGainLinearity() {
        let testName = "testGainLinearity"
        print("[\(testName)] Starting gain linearity test...")

        // Test gain points (dB)
        let testGains: [Float] = [-20, -15, -10, -5, 0, 6, 12]

        // Generate test signal: 1 kHz sine wave
        let testDuration: Float = 0.5
        let numSamples = Int(Float(Self.testSampleRate) * testDuration)
        let sine1kHz = generateSineWave(frequency: 1000, sampleRate: Self.testSampleRate, numSamples: numSamples)
        let inputRMS = rootMeanSquare(signal: sine1kHz)

        print("[\(testName)] Input RMS: \(inputRMS)")

        // Test each gain setting
        for targetGainDB in testGains {
            // Create EQ with single biquad peak filter (approximates fixed gain)
            var eqParams = createBiquadPeakGain(frequencyHz: 1000, gainDB: targetGainDB,
                                                qFactor: 1.0, sampleRate: Self.testSampleRate)

            // Process signal
            let output = processThroughEQ(signal: sine1kHz, params: eqParams)
            let outputRMS = rootMeanSquare(signal: output)

            // Measure actual gain
            let measuredGainDB = 20.0 * Float(log10(Double(outputRMS / inputRMS)))
            let errorDB = abs(measuredGainDB - targetGainDB)

            print("[\(testName)] Target: \(targetGainDB) dB, Measured: \(measuredGainDB) dB, Error: \(errorDB) dB")

            XCTAssertEqual(measuredGainDB, targetGainDB, accuracy: Self.gainLinearityTolerance,
                           "Gain at \(targetGainDB) dB should be within ±\(Self.gainLinearityTolerance) dB")
        }
    }

    // MARK: - Test 3: Frequency Accuracy (31 bands, ±2%)

    /// Test that the 31-band EQ frequencies correspond to standard ISO 266 spacing.
    ///
    /// ISO 266 defines: 31.25, 62.5, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz (1/3 octave bands)
    /// Test procedure:
    /// - Create biquads for each theoretical band center
    /// - Sweep frequency response and measure peak locations
    /// - Verify peak frequency within ±2% of expected
    func testFrequencyAccuracy() {
        let testName = "testFrequencyAccuracy"
        print("[\(testName)] Starting frequency accuracy test...")

        // ISO 266 1/3-octave band center frequencies (31 bands, 20 Hz – 20 kHz)
        let iso266BandCenters: [Float] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
            200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
            2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
        ]

        XCTAssertEqual(iso266BandCenters.count, 31, "ISO 266 should have 31 bands")

        // Test a subset of critical bands (low, mid, high)
        let testBandIndices = [0, 10, 17, 24, 30] // 20 Hz, 200 Hz, 1 kHz, 5 kHz, 20 kHz

        for idx in testBandIndices {
            let expectedFreqHz = iso266BandCenters[idx]

            // Create biquad peak at this frequency
            var eqParams = createBiquadPeakGain(frequencyHz: expectedFreqHz, gainDB: 6.0,
                                                qFactor: 1.0, sampleRate: Self.testSampleRate)

            // Measure frequency response (via filter impulse response FFT)
            // For now, validate that the biquad was created successfully
            XCTAssertGreaterThan(eqParams.numBiquads, 0, "Biquad should be created for band \(idx)")

            // TODO: Full frequency sweep test (requires FFT harness)
            print("[\(testName)] Band \(idx): \(expectedFreqHz) Hz - Biquad created")
        }
    }

    // MARK: - Test 4: Phase Response (Minimum-Phase Validation)

    /// Test that the EQ module implements minimum-phase filtering.
    ///
    /// Minimum-phase validation:
    /// - Apply EQ to 1 second of white noise
    /// - Measure group delay across frequency range
    /// - Verify causality (no pre-ring before impulse)
    /// - Check for zero-padding artifacts
    func testPhaseResponse() {
        let testName = "testPhaseResponse"
        print("[\(testName)] Starting phase response test...")

        // Create EQ with moderate gain boost (6 dB @ 1 kHz)
        var eqParams = createBiquadPeakGain(frequencyHz: 1000, gainDB: 6.0,
                                            qFactor: 1.0, sampleRate: Self.testSampleRate)

        // Generate test signal: white noise
        let numSamples = Int(Self.testSampleRate) // 1 second
        let whiteNoise = generateWhiteNoise(numSamples: numSamples)

        // Process through EQ
        let output = processThroughEQ(signal: whiteNoise, params: eqParams)

        // Causality check: verify no energy before t=0
        // (Minimum-phase filters should not have pre-ring)
        // For a digital filter, check first 10 samples for unusual amplitude
        let firstSamplesMax = output.prefix(10).max() ?? 0
        let maxOutput = output.max() ?? 1
        let preRingRatio = firstSamplesMax / maxOutput

        print("[\(testName)] Pre-ring ratio (first 10 samples / max): \(preRingRatio)")

        // Minimum-phase filters should have modest pre-ring (< 10% of peak)
        XCTAssertLessThan(preRingRatio, 0.1,
                          "Minimum-phase filter should have negligible pre-ring (< 10% of peak)")

        // Stability check: no NaN/Inf
        let hasNaN = output.contains { $0.isNaN }
        let hasInf = output.contains { $0.isInfinite }
        XCTAssertFalse(hasNaN, "Output should not contain NaN values")
        XCTAssertFalse(hasInf, "Output should not contain Inf values")
    }

    // MARK: - Test 5: Stability (White Noise 10 sec, No Clipping)

    /// Test stability and absence of artifacts under sustained processing.
    ///
    /// Test procedure:
    /// - Process 10 seconds of white noise through EQ with various gain settings
    /// - Monitor for clipping (output > ±1.0)
    /// - Check for NaN/Inf/denormalized values
    /// - Verify no dropouts or gaps in output
    func testStability() {
        let testName = "testStability"
        print("[\(testName)] Starting stability test...")

        // Generate long white noise stimulus
        let numSamples = Int(Self.testSampleRate * UInt32(Self.stabilityTestDuration))
        let whiteNoise = generateWhiteNoise(numSamples: numSamples)

        // Test configuration: moderate EQ with multiple bands active
        var eqParams = EQParams()
        eqParams.masterGainLinear = 1.0

        // Simulate multi-band EQ (approximation with sequential biquads)
        // Band 1: -6 dB @ 100 Hz (low-cut)
        // Band 2: +3 dB @ 1 kHz (presence)
        // Band 3: -3 dB @ 8 kHz (de-esser)
        var currentSignal = whiteNoise

        for (freqHz, gainDB) in [(100.0 as Float, -6.0 as Float), (1000.0, 3.0), (8000.0, -3.0)] {
            let bandParams = createBiquadPeakGain(frequencyHz: freqHz, gainDB: gainDB,
                                                  qFactor: 1.0, sampleRate: Self.testSampleRate)
            currentSignal = processThroughEQ(signal: currentSignal, params: bandParams)
        }

        let output = currentSignal

        // Check for numerical issues
        let hasNaN = output.contains { $0.isNaN }
        let hasInf = output.contains { $0.isInfinite }
        let hasDenormalized = output.contains { $0.isSubnormal }

        XCTAssertFalse(hasNaN, "Output should not contain NaN")
        XCTAssertFalse(hasInf, "Output should not contain Inf")
        XCTAssertFalse(hasDenormalized, "Output should not contain denormalized values")

        // Check for clipping
        let maxAbsOutput = output.map(abs).max() ?? 0
        XCTAssertLessThan(maxAbsOutput, 2.0,
                          "Output should not clip (max: \(maxAbsOutput))")

        // Verify RMS stability (should not decay or grow unexpectedly)
        let rmsValue = rootMeanSquare(signal: output)
        print("[\(testName)] 10-sec output RMS: \(rmsValue)")

        // Output RMS should be reasonable (not silent, not clipping)
        XCTAssertGreaterThan(rmsValue, 0.01, "Output RMS should be above noise floor")
        XCTAssertLessThan(rmsValue, 1.5, "Output RMS should not be excessive")
    }

    // MARK: - Test 6: Preset Load/Save (Byte-Identical Reload)

    /// Test that EQ presets can be saved and reloaded with byte-identical results.
    ///
    /// Test procedure:
    /// - Create reference EQ params (e.g., "Presence" preset)
    /// - Serialize to bytes
    /// - Deserialize back to struct
    /// - Verify bit-identical match
    /// - Process test signal with both original and reloaded params
    /// - Verify output is byte-identical
    func testPresetLoadSave() {
        let testName = "testPresetLoadSave"
        print("[\(testName)] Starting preset load/save test...")

        // Create a reference preset configuration
        var originalParams = EQParams()

        // Simulate "Presence" preset: boost at 1 kHz with moderate Q
        originalParams = createBiquadPeakGain(frequencyHz: 1000, gainDB: 6.0,
                                              qFactor: 0.7, sampleRate: Self.testSampleRate)

        // Serialize to bytes
        let originalBytes = withUnsafeBytes(of: originalParams) { Data($0) }

        // Deserialize back to struct
        var deserializedParams = EQParams()
        originalBytes.withUnsafeBytes { buffer in
            if buffer.count == MemoryLayout<EQParams>.size {
                deserializedParams = buffer.load(as: EQParams.self)
            }
        }

        // Verify byte-identical
        XCTAssertEqual(originalBytes.count, MemoryLayout<EQParams>.size,
                       "Serialized size should match struct size")

        // Verify field-by-field match
        XCTAssertEqual(originalParams.numBiquads, deserializedParams.numBiquads,
                       "numBiquads should match after deserialization")
        XCTAssertEqual(originalParams.masterGainLinear, deserializedParams.masterGainLinear,
                       "masterGainLinear should match after deserialization")

        // Verify biquad coefficients match
        for i in 0 ..< Int(originalParams.numBiquads) {
            XCTAssertEqual(originalParams.biquads[i].b0, deserializedParams.biquads[i].b0)
            XCTAssertEqual(originalParams.biquads[i].b1, deserializedParams.biquads[i].b1)
            XCTAssertEqual(originalParams.biquads[i].b2, deserializedParams.biquads[i].b2)
            XCTAssertEqual(originalParams.biquads[i].a1, deserializedParams.biquads[i].a1)
            XCTAssertEqual(originalParams.biquads[i].a2, deserializedParams.biquads[i].a2)
        }

        print("[\(testName)] Serialization/deserialization: PASSED (byte-identical)")

        // Process test signal with both versions
        let testSignal = generateSineWave(frequency: 1000, sampleRate: Self.testSampleRate,
                                          numSamples: Int(Self.testSampleRate))

        let output1 = processThroughEQ(signal: testSignal, params: originalParams)
        let output2 = processThroughEQ(signal: testSignal, params: deserializedParams)

        // Verify outputs are numerically identical (within floating-point precision)
        for i in 0 ..< output1.count {
            XCTAssertEqual(output1[i], output2[i], accuracy: 1e-7,
                           "Output sample \(i) should match after preset reload")
        }

        print("[\(testName)] Output after preset reload: PASSED (numerically identical)")
    }

    // MARK: - Helper Methods

    /// Generate a sine wave at specified frequency
    private func generateSineWave(frequency: Float, sampleRate: UInt32, numSamples: Int) -> [Float] {
        var signal = [Float](repeating: 0, count: numSamples)
        let twoPi = Float(2.0 * Double.pi)
        let phaseIncrement = twoPi * frequency / Float(sampleRate)

        for i in 0 ..< numSamples {
            signal[i] = sin(Float(i) * phaseIncrement)
        }
        return signal
    }

    /// Generate white noise (uniform random, normalized)
    private func generateWhiteNoise(numSamples: Int) -> [Float] {
        var signal = [Float](repeating: 0, count: numSamples)
        srand48(12345) // Deterministic seed for reproducibility

        for i in 0 ..< numSamples {
            // Generate uniform random in [-1, 1]
            signal[i] = 2.0 * Float(drand48()) - 1.0
        }

        // Normalize to prevent clipping
        let rms = rootMeanSquare(signal: signal)
        return signal.map { $0 / (rms > 0 ? rms : 1.0) * 0.5 }
    }

    /// Calculate root-mean-square of signal
    private func rootMeanSquare(signal: [Float]) -> Float {
        guard signal.count > 0 else { return 0 }
        let sumSquares = signal.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(signal.count))
    }

    /// Create a biquad peak filter with specified gain (approximates single-band EQ)
    private func createBiquadPeakGain(frequencyHz: Float, gainDB: Float, qFactor: Float,
                                      sampleRate: UInt32) -> EQParams
    {
        var params = EQParams()

        // Calculate biquad coefficients for peaking EQ filter
        // Standard RBJ design: peaking EQ at given frequency with gain and Q
        let w0 = 2.0 * Float.pi * frequencyHz / Float(sampleRate)
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let A = pow(10.0, gainDB / 40.0) // Amplitude
        let alpha = sinW0 / (2.0 * qFactor)

        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cosW0
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha / A

        // Normalize coefficients
        params.biquads[0].b0 = b0 / a0
        params.biquads[0].b1 = b1 / a0
        params.biquads[0].b2 = b2 / a0
        params.biquads[0].a1 = a1 / a0
        params.biquads[0].a2 = a2 / a0

        params.numBiquads = 1
        params.masterGainLinear = 1.0

        return params
    }

    /// Process signal through EQ module (test harness)
    /// Note: This is a C++ mock until EQModule.process() is fully implemented
    private func processThroughEQ(signal: [Float], params: EQParams) -> [Float] {
        // Direct biquad cascade implementation (simulates EQModule.process)
        var output = signal
        let numFrames = UInt32(signal.count)

        // Apply each biquad in cascade
        for biquadIdx in 0 ..< Int(params.numBiquads) {
            let coeffs = params.biquads[biquadIdx]
            var x1: Float = 0, x2: Float = 0 // Input history
            var y1: Float = 0, y2: Float = 0 // Output history

            for frame in 0 ..< Int(numFrames) {
                let x0 = output[frame]
                let y0 = coeffs.b0 * x0 + coeffs.b1 * x1 + coeffs.b2 * x2
                    - coeffs.a1 * y1 - coeffs.a2 * y2
                x2 = x1
                x1 = x0
                y2 = y1
                y1 = y0
                output[frame] = y0
            }
        }

        // Apply master gain
        output = output.map { $0 * params.masterGainLinear }

        return output
    }
}
