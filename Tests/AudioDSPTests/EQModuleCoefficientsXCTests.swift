import Testing

// ---------------------------------------------------------------------------
// EQModuleCoefficientsTests
//
// Swift Testing migration of EQModuleCoefficientsTests.cpp.
//
// The standalone C++ binary (Tests/EQModuleCoefficientsTests.cpp) uses a
// main() function with assert() — it cannot be run by `swift test` and
// produces no structured output in CI.  These tests call the exact same
// production logic (EQModuleCoefficients::computeBiquadCascade) through the
// C bridge (computeEQCoefficientsC) and run under the standard `swift test` runner.
//
// Test-to-original mapping:
//   testFlatResponsePassThrough  ← C++ Test 1
//   testSingleBandPeak           ← C++ Test 2
//   testExtremeGains             ← C++ Test 3
//   testStability                ← C++ Test 4
//   testMultiplePeaks            ← C++ Test 5
//   testSmallGains               ← C++ Test 6
//   testDifferentSampleRates     ← C++ Test 7
//   testBiquadCountLimit         ← C++ Test 8
//   testConsistency              ← C++ Test 9
//   testExtremeBandIndices       ← C++ Test 10
// ---------------------------------------------------------------------------

@Suite("EQModuleCoefficients")
struct EQModuleCoefficientsTests {
    // Tolerance for floating-point comparisons (matches kFloatTolerance in the C++ tests)
    private static let kTolerance: Float = 1e-5
    private static let kMaxBiquads: Int = 10
    private static let kNumBands: Int = 31

    // -----------------------------------------------------------------------
    // Helper: call computeEQCoefficientsC with a Swift [Float] array
    // -----------------------------------------------------------------------
    private func computeCoeffs(gains: [Float], sampleRate: Float = 48000) -> CEQParams {
        precondition(gains.count == Self.kNumBands)
        var result = CEQParams()
        gains.withUnsafeBufferPointer { buf in
            computeEQCoefficientsC(buf.baseAddress, sampleRate, &result)
        }
        return result
    }

    /// Extract CEQBiquadCoeffs at a given index from CEQParams (fixed C array as tuple).
    private func biquad(at index: Int, in params: CEQParams) -> CEQBiquadCoeffs {
        let mirror = Mirror(reflecting: params.biquads)
        let children = Array(mirror.children)
        precondition(index < children.count && children[index].value is CEQBiquadCoeffs,
                     "biquad index \(index) out of range or wrong type")
        return children[index].value as! CEQBiquadCoeffs // swiftlint:disable:this force_cast
    }

    /// -----------------------------------------------------------------------
    /// Test 1: All gains zero → pass-through (identity biquad)
    /// -----------------------------------------------------------------------
    @Test("Flat (all-zero gains) yields a single pass-through biquad")
    func flatResponsePassThrough() {
        let gains = [Float](repeating: 0.0, count: Self.kNumBands)
        let result = computeCoeffs(gains: gains)

        #expect(Int(result.numBiquads) == 1,
                "All-zero gains must produce exactly 1 identity biquad")

        let b = biquad(at: 0, in: result)
        #expect(abs(b.b0 - 1.0) < Self.kTolerance, "b0 must be 1.0")
        #expect(abs(b.b1) < Self.kTolerance, "b1 must be 0.0")
        #expect(abs(b.b2) < Self.kTolerance, "b2 must be 0.0")
        #expect(abs(b.a1) < Self.kTolerance, "a1 must be 0.0")
        #expect(abs(b.a2) < Self.kTolerance, "a2 must be 0.0")
        #expect(abs(result.masterGainLinear - 1.0) < Self.kTolerance,
                "Master gain must be 1.0")
    }

    /// -----------------------------------------------------------------------
    /// Test 2: Single-band peak at 1 kHz (+6 dB, band index 17)
    /// -----------------------------------------------------------------------
    @Test("Single-band peak at 1 kHz produces valid finite coefficients")
    func singleBandPeak() {
        var gains = [Float](repeating: 0.0, count: Self.kNumBands)
        gains[17] = 6.0
        let result = computeCoeffs(gains: gains)

        #expect(Int(result.numBiquads) >= 1, "Must produce at least 1 biquad")
        #expect(Int(result.numBiquads) <= Self.kMaxBiquads, "Must not exceed kMaxBiquads")

        for i in 0 ..< Int(result.numBiquads) {
            let b = biquad(at: i, in: result)
            #expect(b.b0.isFinite, "b0[\(i)] must be finite")
            #expect(b.b1.isFinite, "b1[\(i)] must be finite")
            #expect(b.b2.isFinite, "b2[\(i)] must be finite")
            #expect(b.a1.isFinite, "a1[\(i)] must be finite")
            #expect(b.a2.isFinite, "a2[\(i)] must be finite")
        }
    }

    /// -----------------------------------------------------------------------
    /// Test 3: Extreme gains (±12 dB)
    /// -----------------------------------------------------------------------
    @Test("Extreme gains (±12 dB) produce stable finite coefficients")
    func extremeGains() {
        for (bandIdx, gain): (Int, Float) in [(10, 12.0), (25, -12.0)] {
            var gains = [Float](repeating: 0.0, count: Self.kNumBands)
            gains[bandIdx] = gain
            let result = computeCoeffs(gains: gains)

            #expect(Int(result.numBiquads) >= 1, "Must produce biquads for \(gain) dB")
            for i in 0 ..< Int(result.numBiquads) {
                let b = biquad(at: i, in: result)
                #expect(b.b0.isFinite, "b0[\(i)] at \(gain) dB must be finite")
                #expect(b.a1.isFinite, "a1[\(i)] at \(gain) dB must be finite")
                #expect(b.a2.isFinite, "a2[\(i)] at \(gain) dB must be finite")
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// Test 4: Stability (Schur-Cohn: poles inside unit circle)
    /// -----------------------------------------------------------------------
    @Test("Schur-Cohn stability: poles are inside the unit circle")
    func stability() {
        var gains = [Float](repeating: 0.0, count: Self.kNumBands)
        gains[15] = 8.0 // 800 Hz boost
        gains[17] = -4.0 // 1 kHz cut
        let result = computeCoeffs(gains: gains)

        for i in 0 ..< Int(result.numBiquads) {
            let b = biquad(at: i, in: result)
            // Schur-Cohn condition 1: |a2| < 1
            #expect(abs(b.a2) < 1.0, "Pole radius |a2| must be < 1 for biquad \(i)")
            // Schur-Cohn condition 2: |a1| ≤ 1 + a2
            #expect(abs(b.a1) <= 1.0 + b.a2 + 1e-5,
                    "Schur-Cohn stability condition must hold for biquad \(i)")
        }
    }

    /// -----------------------------------------------------------------------
    /// Test 5: Multiple peaks (complex presence-boost shape)
    /// -----------------------------------------------------------------------
    @Test("Multiple peaks (presence boost) produce valid coefficients within biquad limit")
    func multiplePeaks() {
        var gains = [Float](repeating: 0.0, count: Self.kNumBands)
        gains[12] = 2.0; gains[15] = 3.0; gains[18] = 4.0
        gains[20] = 3.0; gains[22] = 2.0
        let result = computeCoeffs(gains: gains)

        #expect(Int(result.numBiquads) >= 1)
        #expect(Int(result.numBiquads) <= Self.kMaxBiquads)
        for i in 0 ..< Int(result.numBiquads) {
            let b = biquad(at: i, in: result)
            #expect(b.b0.isFinite, "b0[\(i)] must be finite")
            #expect(b.a2.isFinite, "a2[\(i)] must be finite")
        }
    }

    /// -----------------------------------------------------------------------
    /// Test 6: Very small gains (below 0.5 dB threshold)
    /// -----------------------------------------------------------------------
    @Test("Gains below 0.5 dB threshold produce at least 1 biquad")
    func smallGains() {
        var gains = [Float](repeating: 0.0, count: Self.kNumBands)
        gains[10] = 0.3; gains[15] = 0.2
        let result = computeCoeffs(gains: gains)
        #expect(Int(result.numBiquads) >= 1,
                "Must produce at least 1 biquad even for sub-threshold gains")
    }

    /// -----------------------------------------------------------------------
    /// Test 7: Different sample rates (44.1, 48, 96 kHz)
    /// -----------------------------------------------------------------------
    @Test("Valid finite coefficients at 44.1, 48, and 96 kHz sample rates")
    func differentSampleRates() {
        var gains = [Float](repeating: 0.0, count: Self.kNumBands)
        gains[17] = 6.0
        for sr: Float in [44100, 48000, 96000] {
            let result = computeCoeffs(gains: gains, sampleRate: sr)
            #expect(Int(result.numBiquads) >= 1, "Must produce biquads at \(sr) Hz")
            #expect(Int(result.numBiquads) <= Self.kMaxBiquads,
                    "Must not exceed kMaxBiquads at \(sr) Hz")
            for i in 0 ..< Int(result.numBiquads) {
                let b = biquad(at: i, in: result)
                #expect(b.b0.isFinite, "b0 at \(sr) Hz, biquad \(i)")
                #expect(b.a1.isFinite, "a1 at \(sr) Hz, biquad \(i)")
                #expect(b.a2.isFinite, "a2 at \(sr) Hz, biquad \(i)")
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// Test 8: Biquad count respects the max limit (10)
    /// -----------------------------------------------------------------------
    @Test("Biquad count never exceeds kMaxBiquads (10) even with many active bands")
    func biquadCountLimit() {
        var gains = [Float](repeating: 0.0, count: Self.kNumBands)
        for i in stride(from: 0, to: Self.kNumBands, by: 3) {
            gains[i] = 3.0 + Float(i % 5)
        }
        let result = computeCoeffs(gains: gains)
        #expect(Int(result.numBiquads) > 0, "Must produce at least 1 biquad")
        #expect(Int(result.numBiquads) <= Self.kMaxBiquads,
                "Count must not exceed kMaxBiquads, got \(result.numBiquads)")
    }

    /// -----------------------------------------------------------------------
    /// Test 9: Consistency (same input → same output, two calls)
    /// -----------------------------------------------------------------------
    @Test("computeBiquadCascade is deterministic (same input → identical output)")
    func consistency() {
        var gains = [Float](repeating: 0.0, count: Self.kNumBands)
        gains[17] = 5.0; gains[18] = 3.0; gains[20] = 2.0
        let result1 = computeCoeffs(gains: gains)
        let result2 = computeCoeffs(gains: gains)

        #expect(result1.numBiquads == result2.numBiquads, "Same biquad count both calls")
        for i in 0 ..< Int(result1.numBiquads) {
            let b1 = biquad(at: i, in: result1)
            let b2 = biquad(at: i, in: result2)
            #expect(abs(b1.b0 - b2.b0) < 1e-6, "b0[\(i)] must be deterministic")
            #expect(abs(b1.b1 - b2.b1) < 1e-6, "b1[\(i)] must be deterministic")
            #expect(abs(b1.b2 - b2.b2) < 1e-6, "b2[\(i)] must be deterministic")
            #expect(abs(b1.a1 - b2.a1) < 1e-6, "a1[\(i)] must be deterministic")
            #expect(abs(b1.a2 - b2.a2) < 1e-6, "a2[\(i)] must be deterministic")
        }
    }

    /// -----------------------------------------------------------------------
    /// Test 10: Extreme band indices (20 Hz / 20 kHz)
    /// -----------------------------------------------------------------------
    @Test("Extreme frequency bands (20 Hz and 20 kHz) produce finite coefficients")
    func extremeBandIndices() {
        for (bandIdx, bandHz): (Int, Float) in [(0, 20), (30, 20000)] {
            var gains = [Float](repeating: 0.0, count: Self.kNumBands)
            gains[bandIdx] = bandIdx == 0 ? 5.0 : -5.0
            let result = computeCoeffs(gains: gains)
            #expect(Int(result.numBiquads) >= 1, "Must produce biquads for \(bandHz) Hz")
            #expect(biquad(at: 0, in: result).b0.isFinite,
                    "b0 must be finite for \(bandHz) Hz band")
        }
    }
}
