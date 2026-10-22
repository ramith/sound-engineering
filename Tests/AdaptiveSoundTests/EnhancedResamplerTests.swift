@testable import AdaptiveSound
import Foundation
import Testing

// MARK: - The Enhanced resampler keeps the treble, through the real bridge (council C-26, KI-SND-02)

//
// `make gate`'s SRC check measures the converter (AudioFormatKit's `StreamingResampler`) on every
// rate pair. This one proves the app plays through it: a 44.1 kHz file of two equal tones, 1 kHz and
// 20 kHz, rendered by the real bridge on an offline engine (`EnhancedTransportRig`, the resampler
// sub-path, the real effects chain). The old Normal converter played 20 kHz 8.25 dB down; the two
// must now come out level.

@Suite("Enhanced resampler — the treble reaches the output (C-26)", .serialized, .timeLimit(.minutes(5)))
struct EnhancedResamplerTests {
    /// Least-squares amplitude of the sinusoid at `frequency` in `samples` (48 kHz). The two tones
    /// are 19 kHz apart, so over 0.4 s neither leaks into the other's reading (< −80 dB).
    static func amplitude(_ samples: ArraySlice<Float>, frequency: Double) -> Double {
        var sumSS = 0.0, sumCC = 0.0, sumSC = 0.0, sumXS = 0.0, sumXC = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(index) / EnhancedTransportRig.graphRate
            let (sine, cosine) = (sin(phase), cos(phase))
            sumSS += sine * sine
            sumCC += cosine * cosine
            sumSC += sine * cosine
            sumXS += Double(sample) * sine
            sumXC += Double(sample) * cosine
        }
        let determinant = sumSS * sumCC - sumSC * sumSC
        let partA = (sumXS * sumCC - sumXC * sumSC) / determinant
        let partB = (sumXC * sumSS - sumXS * sumSC) / determinant
        return (partA * partA + partB * partB).squareRoot()
    }

    @Test("a 44.1 kHz file plays 20 kHz as loud as 1 kHz (within 0.1 dB)")
    func trebleSurvivesTheResampler() async throws {
        let rig = try await EnhancedTransportRig(path: .resampler, name: "treble", tones: [1000, 20000])
        let output = try #require(await rig.samples(seconds: 0.5))
        // 0.1 … 0.5 s: past the start, inside the primed lead.
        let span = output[4800 ..< 24000]
        let low = Self.amplitude(span, frequency: 1000)
        let high = Self.amplitude(span, frequency: 20000)
        try #require(low > 0.01, "the 1 kHz tone reaches the output")
        let treble = 20 * log10(high / low)
        #expect(abs(treble) <= 0.1, "20 kHz is \(treble) dB re 1 kHz (the Normal converter: −8.25 dB)")
        await rig.finish()
    }
}
