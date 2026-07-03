import Darwin
import Testing

// MARK: - EQTests processing helpers, CEQParams factories, and signal generators.

//
// Split out of EQTests.swift (best-practices decomposition: keep the `@Suite` struct's own
// body — the `@Test` cases — under SwiftLint `type_body_length`/`file_length`). These are
// `internal` (not `private`) so the `@Test` functions in EQTests.swift can call them.

extension EQTests {
    // MARK: - Processing Helpers

    /// Process via the in-Swift biquad cascade (reference / sanity-check path).
    func processViaSwiftReference(signal: [Float], params: CEQParams) -> [Float] {
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
    func processViaRealEQModule(signal: [Float], params: CEQParams) -> [Float] {
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
    func processViaRealEQModuleStream(signal: [Float], params: CEQParams) -> [Float] {
        var buffer = signal
        var mutableParams = params
        withUnsafeMutablePointer(to: &mutableParams) { paramsPtr in
            eqModuleProcessStreamC(&buffer, paramsPtr, UInt32(signal.count))
        }
        return buffer
    }

    // MARK: - CEQParams Factories

    func makeFlatCEQParams() -> CEQParams {
        var params = CEQParams()
        params.numBiquads = 0
        params.masterGainLinear = 1.0
        return params
    }

    func makePeakBiquadCEQParams(frequencyHz: Float, gainDB: Float,
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

    func biquadCoeffsAt(index: Int, in params: CEQParams) -> CEQBiquadCoeffs {
        let mirror = Mirror(reflecting: params.biquads)
        let children = Array(mirror.children)
        guard index < children.count,
              let coeffs = children[index].value as? CEQBiquadCoeffs
        else { return CEQBiquadCoeffs() }
        return coeffs
    }

    // MARK: - Signal Generators

    func generateSineWave(frequency: Float, sampleRate: UInt32,
                          numSamples: Int) -> [Float] {
        let phaseInc = 2.0 * Float.pi * frequency / Float(sampleRate)
        return (0 ..< numSamples).map { Darwin.sin(Float($0) * phaseInc) }
    }

    /// Generates a reproducible pseudo-random white-noise signal. Seeded (not
    /// `SystemRandomNumberGenerator`) so the stability test is deterministic across runs;
    /// uses `Float.random(in:using:)` over a splitmix64 `RandomNumberGenerator`, not the
    /// legacy C `srand48`/`drand48` pair.
    func generateWhiteNoise(numSamples: Int) -> [Float] {
        var rng = SplitMix64(seed: 12345)
        var signal = [Float](repeating: 0, count: numSamples)
        for idx in 0 ..< numSamples {
            signal[idx] = Float.random(in: -1.0 ... 1.0, using: &rng)
        }
        let rms = rootMeanSquare(signal: signal)
        return signal.map { $0 / (rms > 0 ? rms : 1.0) * 0.5 }
    }

    func rootMeanSquare(signal: [Float]) -> Float {
        guard !signal.isEmpty else { return 0 }
        let sumSq = signal.reduce(0.0) { $0 + $1 * $1 }
        return Darwin.sqrt(sumSq / Float(signal.count))
    }

    func gainDBValue(output: [Float], inputRMS: Float) -> Float {
        let outRMS = rootMeanSquare(signal: output)
        return Float(20.0) * Float(Darwin.log10(Double(outRMS / inputRMS)))
    }

    /// RMS over the SETTLED TAIL (samples `[skip, end)`), excluding the leading
    /// transient (filter turn-on + master-gain ramp). For a pure tone through an LTI
    /// filter the tail is a steady sinusoid, so its RMS is the exact steady-state level.
    func settledRMS(signal: [Float], skip: Int) -> Float {
        guard skip < signal.count else { return rootMeanSquare(signal: signal) }
        return rootMeanSquare(signal: Array(signal[skip...]))
    }

    /// Steady-state gain in dB: settled-tail output RMS vs settled-tail input RMS.
    func settledGainDB(output: [Float], inputRMS: Float, skip: Int) -> Float {
        let outRMS = settledRMS(signal: output, skip: skip)
        return Float(20.0) * Float(Darwin.log10(Double(outRMS / inputRMS)))
    }
}

/// A small deterministic, seedable `RandomNumberGenerator` (splitmix64) so test signal
/// generation is reproducible across runs without relying on the legacy C `drand48` RNG.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
