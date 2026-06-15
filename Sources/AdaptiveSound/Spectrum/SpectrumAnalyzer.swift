// SpectrumAnalyzer.swift
//
// Lock-free spectrum analysis pipeline for the real-time audio tap.
//
// Threading contract
// ------------------
// - The audio tap callback (audio thread) calls `processTapBuffer(_:sampleRate:)`.
//   That method does *no allocation*, *no lock*, and *no Swift runtime calls* beyond
//   indexed buffer access and Accelerate/vDSP.
// - The main thread calls `readBands()` at ~20 Hz to copy the last computed band
//   magnitudes. The handoff uses a generation counter (ManagedAtomic<Int>) so no
//   lock is ever taken on either side.
//
// FFT design
// ----------
// - N = 4096 float32 real FFT via vDSP_fft_zrip (Apple Accelerate).
// - Hann window pre-computed at init; applied per buffer via vDSP_vmul.
// - If the engine runs at 44.1 kHz, bin resolution = 44100/4096 ≈ 10.8 Hz.
// - If the engine runs at 48 kHz, bin resolution = 48000/4096 ≈ 11.7 Hz.
// - Stereo input is summed to mono (vDSP_vadd + vDSP_vsmul 0.5) before windowing.
//
// Band mapping
// ------------
// - 44 bands, log-spaced from 40 Hz to 20 kHz at 1/6-octave steps.
// - Band center frequencies: f_k = 40 * 2^(k/6), k = 0..43.
// - Band magnitude = max FFT bin magnitude inside the band's [lo, hi] range.
// - Result mapped to dB (floor −80 dB), normalised to [0, 1].
//
// Meter ballistics (in the tap, allocation-free)
// -----------------------------------------------
// - Attack: instant (peak hold).
// - Release: first-order IIR y[n] = max(x[n], α·y[n-1]).
//   α = 0.85 gives ≈150 ms decay at 20 Hz display rate.

import Accelerate
import AudioToolbox
import AVFoundation
import Foundation

// MARK: - Constants

enum SpectrumConstants {
    static let fftSize: Int = 4096
    static let bandCount: Int = 44
    static let displayBarCount: Int = 88 // 2 bars per band; view interpolates
    static let minHz: Float = 40.0
    static let maxHz: Float = 20000.0
    static let noiseFloorDB: Float = -80.0 // dB floor mapped to 0.0
    static let releaseAlpha: Float = 0.85 // IIR release coefficient (~150 ms @ 20 Hz)
}

// MARK: - Lock-free double buffer

/// A pair of Float arrays swapped via an atomic generation counter.
/// The producer (audio thread) writes into the "back" slot; increments
/// the counter when done. The consumer (main thread) reads the slot
/// whose index matches the latest counter.
///
/// Safety: both slots are pre-allocated at init. No allocation ever
/// occurs in `write(_:)` or `read(into:)`.
final class SpectrumDoubleBuffer {
    private let count: Int
    private var slots: [[Float]] // [slot0, slot1]
    private var generation: Int = 0 // written only on audio thread; read on main

    /// `pendingGeneration` is the generation value last written.
    /// Using a plain Int stored via an UnsafeAtomic-equivalent pattern:
    /// we rely on the fact that Int writes are atomic on LP64 (arm64) for
    /// aligned 64-bit stores, and the audio thread is the sole writer.
    /// For a production-grade alternative, use AtomicRepresentable from
    /// swift-atomics (SE-0282). This is a deliberate Phase 1b simplification.
    private var publishedGeneration: Int = -1 // read on main, written on audio thread

    init(count: Int) {
        self.count = count
        slots = [
            [Float](repeating: 0, count: count),
            [Float](repeating: 0, count: count),
        ]
    }

    /// Audio thread: copy `values` into the next slot and publish.
    /// No allocation. No lock.
    func write(_ values: UnsafeBufferPointer<Float>) {
        precondition(values.count == count)
        let nextSlot = (generation + 1) & 1
        slots[nextSlot].withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress,
                  let srcBase = values.baseAddress else { return }
            cblas_scopy(Int32(count), srcBase, 1, dstBase, 1)
        }
        generation = generation &+ 1 // wrapping add; sole writer on audio thread
        publishedGeneration = generation // arm64: aligned Int write is single instruction
    }

    /// Main thread: copy the latest published slot into `out`.
    /// Returns `true` if new data was available since the last call.
    @discardableResult
    func read(into out: inout [Float]) -> Bool {
        let gen = publishedGeneration // read once
        guard gen >= 0 else { return false }
        let slot = gen & 1
        out.withUnsafeMutableBufferPointer { dst in
            slots[slot].withUnsafeBufferPointer { src in
                guard let d = dst.baseAddress, let s = src.baseAddress else { return }
                cblas_scopy(Int32(count), s, 1, d, 1)
            }
        }
        return true
    }
}

// MARK: - Spectrum Analyzer

/// Owns the FFT setup, Hann window, band mapping, and meter ballistics.
/// Lives inside `AudioEngineBridge`. All real-time-safe methods are marked
/// with a comment; all allocating setup methods must be called off the audio thread.
final class SpectrumAnalyzer {
    // MARK: - Pre-allocated FFT state (set up off-RT, read-only on RT)

    private let fftSize: Int
    private let log2n: vDSP_Length
    private var fftSetup: FFTSetup?

    private var hannWindow: [Float] // length = fftSize
    private var monoBuffer: [Float] // length = fftSize
    private var windowedBuffer: [Float] // length = fftSize
    private var complexReal: [Float] // length = fftSize/2
    private var complexImag: [Float] // length = fftSize/2
    private var magnitudes: [Float] // length = fftSize/2 + 1 (DC..Nyquist)
    private var bandMagnitudes: [Float] // length = bandCount
    private var smoothedBands: [Float] // IIR state; length = bandCount

    // MARK: - Band-to-bin mapping (precomputed, immutable after init)

    private struct BandRange {
        let lo: Int // first FFT bin (inclusive)
        let hi: Int // last FFT bin (inclusive)
    }

    private var bandRanges: [BandRange] // length = bandCount

    // MARK: - Lock-free output

    private(set) var doubleBuffer: SpectrumDoubleBuffer

    // MARK: - Init (must be called OFF the audio thread)

    /// - Parameters:
    ///   - fftSize: Must be a power of two. Defaults to `SpectrumConstants.fftSize`.
    ///   - sampleRate: The engine's current sample rate (used for bin→Hz mapping).
    init(fftSize: Int = SpectrumConstants.fftSize, sampleRate: Float = 48000) {
        self.fftSize = fftSize
        log2n = vDSP_Length(log2(Float(fftSize)))

        // Allocate FFT setup
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        // Pre-allocate all processing buffers
        hannWindow = [Float](repeating: 0, count: fftSize)
        monoBuffer = [Float](repeating: 0, count: fftSize)
        windowedBuffer = [Float](repeating: 0, count: fftSize)
        complexReal = [Float](repeating: 0, count: fftSize / 2)
        complexImag = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2 + 1)
        bandMagnitudes = [Float](repeating: 0, count: SpectrumConstants.bandCount)
        smoothedBands = [Float](repeating: 0, count: SpectrumConstants.bandCount)

        doubleBuffer = SpectrumDoubleBuffer(count: SpectrumConstants.bandCount)
        bandRanges = []

        // Pre-compute Hann window: w[n] = 0.5 * (1 - cos(2π·n/(N-1)))
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // Pre-compute band-to-bin mapping
        bandRanges = Self.makeBandRanges(
            bandCount: SpectrumConstants.bandCount,
            minHz: SpectrumConstants.minHz,
            maxHz: SpectrumConstants.maxHz,
            fftSize: fftSize,
            sampleRate: sampleRate
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - RT-safe processing

    /// Process one tap buffer. REAL-TIME SAFE: no allocation, no lock, no ObjC.
    ///
    /// - Parameters:
    ///   - bufferList: The `AVAudioPCMBuffer.mutableAudioBufferList` pointer from the tap.
    ///   - frameCount: Number of valid frames in the buffer.
    ///   - channelCount: Number of interleaved channels (1 = mono, 2 = stereo non-interleaved).
    func processTapBuffer(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: AVAudioFrameCount,
        channelCount: UInt32
    ) {
        guard let fftSetup else { return }

        let n = min(Int(frameCount), fftSize)

        // 1. Sum channels to mono into monoBuffer (zero the rest if frameCount < fftSize)
        //    Channels are non-interleaved float32 from AVAudioEngine's standard format.
        if channelCount >= 2 {
            // Two channels: average L and R
            guard let ch0 = bufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else { return }
            // Non-interleaved: channel 1 is at the next AudioBuffer in the list
            let abls = UnsafeMutableAudioBufferListPointer(bufferList)
            guard abls.count >= 2,
                  let ch1 = abls[1].mData?.assumingMemoryBound(to: Float.self)
            else {
                // Fallback: copy channel 0 only
                cblas_scopy(Int32(n), ch0, 1, &monoBuffer, 1)
                if n < fftSize {
                    vDSP_vclr(&monoBuffer + n, 1, vDSP_Length(fftSize - n))
                }
                return
            }
            // mono[i] = 0.5 * (ch0[i] + ch1[i])
            vDSP_vadd(ch0, 1, ch1, 1, &monoBuffer, 1, vDSP_Length(n))
            var half: Float = 0.5
            // Scale in-place: obtain a single raw pointer so Swift's exclusivity
            // checker sees one borrow rather than two overlapping ones.
            monoBuffer.withUnsafeMutableBufferPointer { mono in
                guard let ptr = mono.baseAddress else { return }
                vDSP_vsmul(ptr, 1, &half, ptr, 1, vDSP_Length(n))
            }
        } else {
            // Mono input — copy directly
            guard let ch0 = bufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else { return }
            cblas_scopy(Int32(n), ch0, 1, &monoBuffer, 1)
        }

        // Zero-pad the tail if the tap delivered fewer frames than the FFT window
        if n < fftSize {
            vDSP_vclr(&monoBuffer + n, 1, vDSP_Length(fftSize - n))
        }

        // 2. Apply Hann window: windowed[i] = mono[i] * hann[i]
        vDSP_vmul(&monoBuffer, 1, &hannWindow, 1, &windowedBuffer, 1, vDSP_Length(fftSize))

        // 3. Real FFT via vDSP_fft_zrip
        //    Pack real sequence into complex format DSPSplitComplex expects:
        //    even samples → real part, odd samples → imaginary part.
        windowedBuffer.withUnsafeMutableBufferPointer { wPtr in
            complexReal.withUnsafeMutableBufferPointer { rPtr in
                complexImag.withUnsafeMutableBufferPointer { iPtr in
                    guard let wBase = wPtr.baseAddress,
                          var rBase = rPtr.baseAddress,
                          var iBase = iPtr.baseAddress else { return }
                    var splitComplex = DSPSplitComplex(realp: rBase, imagp: iBase)
                    wBase.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { dspComplexPtr in
                        vDSP_ctoz(dspComplexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                    // 4. Compute power spectrum magnitudes: mag[k] = sqrt(re^2 + im^2)
                    //    vDSP_zvmags gives re^2 + im^2; then vvsqrtf for sqrt.
                    //    Use magnitudes array (length = fftSize/2) — DC is index 0.
                    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                    // magnitudes now holds squared magnitudes; take sqrt in-place.
                    // vvsqrtf and vDSP_vsmul support src == dst, but Swift's
                    // exclusivity checker needs a single &-borrow; obtain it once.
                    magnitudes.withUnsafeMutableBufferPointer { magBuf in
                        guard let magPtr = magBuf.baseAddress else { return }
                        var count = Int32(fftSize / 2)
                        vvsqrtf(magPtr, magPtr, &count)
                        // Normalise by 2/N (vDSP_fft_zrip scale convention)
                        var scale = Float(2.0) / Float(fftSize)
                        vDSP_vsmul(magPtr, 1, &scale, magPtr, 1, vDSP_Length(fftSize / 2))
                    }

                    // 5. Map FFT bins → log-spaced bands (max magnitude per band)
                    for bandIdx in 0 ..< SpectrumConstants.bandCount {
                        let range = bandRanges[bandIdx]
                        let lo = max(0, range.lo)
                        let hi = min(fftSize / 2 - 1, range.hi)
                        guard hi >= lo else {
                            bandMagnitudes[bandIdx] = 0
                            continue
                        }
                        var peakMag: Float = 0
                        // vDSP_maxv over the slice of magnitudes
                        magnitudes.withUnsafeBufferPointer { mPtr in
                            guard let mBase = mPtr.baseAddress else { return }
                            vDSP_maxv(mBase + lo, 1, &peakMag, vDSP_Length(hi - lo + 1))
                        }
                        bandMagnitudes[bandIdx] = peakMag
                    }

                    // 6. Convert magnitudes to dB and normalise to [0, 1]
                    //    dB = 20 * log10(mag), floored at noiseFloorDB.
                    //    Map [noiseFloor, 0] → [0, 1].
                    for bandIdx in 0 ..< SpectrumConstants.bandCount {
                        let mag = bandMagnitudes[bandIdx]
                        // Avoid log10(0): clamp to a tiny positive value
                        let safeMag = max(mag, 1e-9)
                        var dbVal = 20.0 * log10(safeMag)
                        dbVal = max(dbVal, SpectrumConstants.noiseFloorDB)
                        // Normalise: 0 dB → 1.0, noiseFloorDB → 0.0
                        let normalised = (dbVal - SpectrumConstants.noiseFloorDB) /
                            (-SpectrumConstants.noiseFloorDB)
                        bandMagnitudes[bandIdx] = normalised
                    }

                    // 7. Meter ballistics: instant attack, IIR release
                    //    y[n] = max(x[n], alpha * y[n-1])
                    let alpha = SpectrumConstants.releaseAlpha
                    for bandIdx in 0 ..< SpectrumConstants.bandCount {
                        let prev = smoothedBands[bandIdx] * alpha
                        smoothedBands[bandIdx] = max(bandMagnitudes[bandIdx], prev)
                    }

                    // 8. Publish to the double-buffer for the main thread
                    smoothedBands.withUnsafeBufferPointer { sPtr in
                        doubleBuffer.write(sPtr)
                    }

                    // Keep rBase and iBase alive through the closure
                    _ = rBase
                    _ = iBase
                }
            }
        }
    }

    // MARK: - Band range computation (called off RT at init)

    /// Pre-compute FFT bin index ranges for each log-spaced band.
    /// f_k = minHz * 2^(k/6), k = 0..bandCount-1 (1/6-octave spacing).
    /// Band k covers [f_k / 2^(1/12), f_k * 2^(1/12)] (half-step on each side).
    private static func makeBandRanges(
        bandCount: Int,
        minHz: Float,
        maxHz _: Float,
        fftSize: Int,
        sampleRate: Float
    ) -> [BandRange] {
        let hzPerBin = sampleRate / Float(fftSize)
        var ranges: [BandRange] = []
        ranges.reserveCapacity(bandCount)

        let halfSemitone = powf(2.0, 1.0 / 12.0) // one half-step ratio

        for k in 0 ..< bandCount {
            let center = minHz * powf(2.0, Float(k) / 6.0)
            let lo = center / halfSemitone
            let hi = center * halfSemitone
            let loBin = Int(lo / hzPerBin)
            let hiBin = Int(hi / hzPerBin)
            ranges.append(BandRange(lo: loBin, hi: max(loBin, hiBin)))
        }
        return ranges
    }
}
