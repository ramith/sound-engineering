import Accelerate
@preconcurrency import AVFoundation
import Foundation

// MARK: - Reference Tone Generation (using vDSP)

/// Synthetic test-tone generation, factored out of `AudioEngineBridge.swift` into a same-module
/// extension to keep the core class body focused (it touches no private engine state — only its
/// parameters + Accelerate — so a separate file is safe). Used as the fallback "signal" when
/// playback is started without a file.
extension AudioEngineBridge {
    func generateReferenceTone(
        frequency: Float,
        duration: Float,
        sampleRate: Float
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        let floatData = floatChannelData[0]

        // Generate sine wave using vDSP
        // Phase increment per sample: 2π * frequency / sampleRate
        let phaseIncrement = 2.0 * Float.pi * frequency / sampleRate

        // Build angle array: angle[i] = phaseIncrement * i
        var angles = [Float](repeating: 0, count: Int(frameCount))
        for sampleIndex in 0 ..< Int(frameCount) {
            angles[sampleIndex] = phaseIncrement * Float(sampleIndex)
        }

        // Compute sine using vForce.sin (Accelerate, vectorised single-precision)
        let sineValues = vForce.sin(angles)
        sineValues.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            UnsafeMutableBufferPointer(start: floatData, count: Int(frameCount))
                .baseAddress
                .map { dst in
                    // Straight contiguous copy (was cblas_scopy stride-1); non-allocating.
                    dst.update(from: srcBase, count: Int(frameCount))
                }
        }

        // Apply gain
        var gain = Float(0.3)
        vDSP_vsmul(floatData, 1, &gain, floatData, 1, vDSP_Length(frameCount))

        return buffer
    }
}
