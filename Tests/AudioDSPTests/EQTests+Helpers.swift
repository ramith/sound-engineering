import AudioDSPTestBridge
import Darwin
import Testing

// MARK: - EQTests bridge calls and signal helpers

// Split out of EQTests.swift so the suite body stays the @Test cases. `internal` so the tests
// can call them.

extension EQTests {
    /// Stream `signal` through the production EQ designed for `points`; nil when rejected.
    func stream(_ signal: [Float], points: [Float]) -> [Float]? {
        var buffer = signal
        let accepted = eqStreamC(&buffer, UInt32(buffer.count), points, UInt32(points.count), 48000)
        return accepted ? buffer : nil
    }

    /// The design's played response at the 31 centres; nil when rejected.
    func playedCentres(points: [Float]) -> [Float]? {
        var centres = [Float](repeating: 0, count: 31)
        let accepted = eqPlayedCentresC(points, UInt32(points.count), 48000, &centres)
        return accepted ? centres : nil
    }

    /// The steady-state gain (dB) a 2 s sine at `toneHz` plays through the EQ: output vs input RMS
    /// over the last second (the bells have rung in by then).
    func settledGainDb(points: [Float], toneHz: Double) throws -> Float {
        let count = 96000
        let signal = (0 ..< count).map { Float(0.25 * Darwin.sin(2 * Double.pi * toneHz * Double($0) / 48000)) }
        let output = try #require(stream(signal, points: points))
        let input = rootMeanSquare(signal: Array(signal[48000...]))
        let played = rootMeanSquare(signal: Array(output[48000...]))
        return 20 * Darwin.log10(played / input)
    }

    /// Reproducible white noise (splitmix64), RMS 0.5.
    func generateWhiteNoise(numSamples: Int) -> [Float] {
        var rng = SplitMix64(seed: 12345)
        let signal = (0 ..< numSamples).map { _ in Float.random(in: -1.0 ... 1.0, using: &rng) }
        let rms = rootMeanSquare(signal: signal)
        return signal.map { $0 / (rms > 0 ? rms : 1.0) * 0.5 }
    }

    func rootMeanSquare(signal: [Float]) -> Float {
        guard !signal.isEmpty else { return 0 }
        let sumSq = signal.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Float(Darwin.sqrt(sumSq / Double(signal.count)))
    }
}

/// A small deterministic, seedable `RandomNumberGenerator` (splitmix64) so test signals are
/// reproducible across runs.
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
