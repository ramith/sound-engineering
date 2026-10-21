import AudioDSPTestBridge
import Darwin
import Testing

/// The production graphic EQ, end to end through the C bridge (`EQTestBridge.h`): the
/// `GraphicEQDesigner` solve and the real-time `EQModule` SVF cascade, streamed in 512-frame
/// blocks like the render thread. The C++ gate (`make gate`) owns the oracle accuracy and the
/// transition/path proofs; these pin what a Swift caller relies on: the identity is bit-exact, a
/// tone plays at the level the design reads back, and the cascade stays stable and finite.
@Suite("EQModule signal path (graphic EQ)")
struct EQTests {
    private let sampleRate = 48000.0

    /// Measured vs read-back at a centre: the settled sine through double SVFs matches the
    /// complex-form read-back to ~1e-6 dB; 0.02 dB absorbs float32 I/O and the RMS window.
    private let readbackTolerance: Float = 0.02

    @Test("Flat points are a bit-exact pass-through")
    func flatIsBitExact() throws {
        let signal = generateWhiteNoise(numSamples: 48000)
        let output = try #require(stream(signal, points: [Float](repeating: 0, count: 31)))
        #expect(output == signal)
    }

    @Test("A single band plays the gain the design reads back, at 1 kHz",
          arguments: [Float(-12), -6, 6, 12])
    func singleBandGainMatchesReadback(gainDb: Float) throws {
        var points = [Float](repeating: 0, count: 31)
        points[17] = gainDb // 1 kHz
        let measured = try settledGainDb(points: points, toneHz: 1000)
        let expected = try #require(playedCentres(points: points))[17]
        #expect(abs(measured - expected) <= readbackTolerance, "\(gainDb) dB: \(measured) vs \(expected)")
        #expect(abs(measured - gainDb) <= 0.3, "\(gainDb) dB: played \(measured)")
    }

    @Test("A jagged curve plays its read-back at several centres")
    func jaggedCurveMatchesReadback() throws {
        let points = (0 ..< 31).map { Float($0 % 2 == 0 ? 12 : -12) }
        let centres = try #require(playedCentres(points: points))
        for band in [10, 17, 24] {
            let toneHz = Darwin.pow(10, 1.3 + 0.1 * Double(band))
            let measured = try settledGainDb(points: points, toneHz: toneHz)
            #expect(abs(measured - centres[band]) <= readbackTolerance, "band \(band)")
        }
    }

    @Test("10 s of white noise through the hardest curve stays finite and bounded")
    func noiseStability() throws {
        let points = (0 ..< 31).map { Float($0 % 2 == 0 ? 12 : -12) }
        let signal = generateWhiteNoise(numSamples: Int(sampleRate) * 10)
        let output = try #require(stream(signal, points: points))
        #expect(output.allSatisfy { $0.isFinite })
        #expect(output.allSatisfy { $0 == 0 || $0.isNormal }, "no subnormal output")
        #expect(rootMeanSquare(signal: output) < 20 * rootMeanSquare(signal: signal))
    }

    @Test("The impulse response decays: the slowest bell rings down within 2 s, no instability")
    func impulseDecays() throws {
        var impulse = [Float](repeating: 0, count: 96000)
        impulse[0] = 1
        var points = [Float](repeating: 0, count: 31)
        points[0] = 12 // the slowest band, 20 Hz
        let output = try #require(stream(impulse, points: points))
        #expect(output.allSatisfy { $0.isFinite })
        let head = rootMeanSquare(signal: Array(output[0 ..< 9600]))
        let tail = rootMeanSquare(signal: Array(output[86400...]))
        #expect(tail < head * 1e-4, "the 20 Hz bell must ring down within 2 s")
    }

    @Test("A design the engine cannot play is rejected, the buffer untouched")
    func rejectedDesignLeavesBuffer() {
        var signal: [Float] = [0.25, -0.5, 0.75]
        var nanPoints = [Float](repeating: 0, count: 31)
        nanPoints[4] = .nan
        #expect(!eqStreamC(&signal, UInt32(signal.count), nanPoints, 31, sampleRate))
        #expect(!eqStreamC(&signal, UInt32(signal.count), [Float](repeating: 0, count: 31), 31, 32000))
        #expect(!eqStreamC(&signal, UInt32(signal.count), [Float](repeating: 0, count: 30), 30, sampleRate))
        #expect(signal == [0.25, -0.5, 0.75])
    }
}
