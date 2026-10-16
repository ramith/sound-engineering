// SpectrumAnalyzer.swift
//
// The analyser behind every live spectrum — Now Playing's lens, the EQ's silhouette, Monitoring's
// before / after halves: a tap's audio in, the 44 bands' levels out, handed to the main thread.
//
// What it measures (council C-51; panel P1 D53, D54 — held to it by `SpectrumAnalyzerOracleTests`):
// - Every sample. A short-time FFT runs over the stream as it arrives, a Hann window of ≈ 85 ms
//   hopping by half a window, so each sample is analysed twice whatever buffer size the tap delivers
//   (100–400 ms, Apple's range). A frame is how loud each band got over one tap buffer — a
//   peak-reading display — published once per buffer. (Before: the first 4096 frames of each buffer
//   only, 21 % of the audio at 192 kHz.)
// - The same resolution at every rate. The window keeps the shipped 48 kHz window's length in time
//   (4096 frames), as a power of two: 4096 at 44.1 / 48 kHz, 8192 at 88.2 / 96, 16 384 at
//   176.4 / 192. Its bins are ≈ 11 Hz apart at every rate, zero-padded ×2 to ≈ 5.5 Hz, which bounds
//   the window's scalloping to 0.35 dB. (Before: 4096 at every rate, 47 Hz bins at 192 kHz.)
// - True levels. A sine of amplitude A reads A: each bin's magnitude is divided by the window's sum
//   (vDSP's real FFT returns twice the DFT, which the sine's two-sided split cancels), so a
//   full-scale sine reads 0 dBFS. (Before: +4.26 dB — the normalised Hann's gain taken as 1/2.)
// - Bands, not bins. Each band owns the bins inside its 1/6-octave span; no bin is in two bands. A
//   band narrower than a bin reads the spectrum at its centre. The window's mean is removed first:
//   DC is not music, and no band holds it. (Before: shared bins, and DC in the lowest bands.)
// - Meter ballistics: instant attack; release y = max(x, α·y) on the display's 0…1 scale, with
//   α = exp(−Δt / τ) for the buffer's own duration Δt — the shipped 0.85 per 100 ms buffer,
//   now whatever buffer size the system picks.
//
// Threading: `init` allocates everything (the FFT setup, every buffer, the band table) off the tap
// thread. The tap thread alone calls `processTapBuffer`: raw-pointer access and Accelerate only — no
// allocation, lock, ARC, copy-on-write or exclusivity check. Frames reach the main thread through
// `frames`, a wait-free triple buffer.

import Accelerate
import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

// MARK: - Spectrum Analyzer

/// One analyser: one tap point (the mixer's output, or one channel of the player or the effects AU).
///
/// `@unchecked Sendable` invariant: everything the tap thread touches is allocated at `init` and
/// owned by that ONE tap thread from then on; the only cross-thread hand-over is `frames` (itself an
/// audited SPSC triple buffer). That lets the tap closure capture the analyser strongly at install
/// and use it with no lock, queue or reference counting.
final class SpectrumAnalyzer: @unchecked Sendable {
    /// The frames, tap thread → main thread: each band's level in 0…1 over the display's dB range
    /// (`SpectrumConstants.noiseFloorDB` … 0 dBFS).
    let frames: SpectrumTripleBuffer
    /// The rate the analyser was built for.
    let sampleRate: Double
    /// Samples per analysis window at this rate (`windowLength(sampleRate:)`).
    let windowLength: Int

    private let fftLength: Int
    private let log2FFTLength: vDSP_Length
    private let hop: Int
    private let fftSetup: FFTSetup
    /// A sine's amplitude per unit of FFT magnitude: 1 / the window's sum.
    private let amplitudePerMagnitude: Float
    /// Which bins each band reads.
    private let layout: RealtimeBandLayout

    private let hann: UnsafeMutablePointer<Float> // windowLength
    private let history: UnsafeMutablePointer<Float> // windowLength: the latest samples, a ring
    private let windowed: UnsafeMutablePointer<Float> // fftLength: the window's samples, zero-padded
    private let real: UnsafeMutablePointer<Float> // fftLength / 2
    private let imaginary: UnsafeMutablePointer<Float> // fftLength / 2
    private let power: UnsafeMutablePointer<Float> // fftLength / 2: |X|² per bin
    private let bufferPeak: UnsafeMutablePointer<Float> // bandCount: the loudest amplitude this buffer
    private let shown: UnsafeMutablePointer<Float> // bandCount: the published levels (ballistics state)
    private let tap: UnsafeMutablePointer<TapState>

    /// The tap thread's running state.
    private struct TapState {
        /// Where the next sample goes in `history` (also its oldest sample).
        var writeIndex = 0
        /// Samples since the last window was analysed.
        var sinceHop = 0
        /// Windows analysed into `bufferPeak` since the last publish.
        var windows = 0
        /// Audio since the last publish, in seconds: the release's Δt.
        var unpublishedSeconds = 0.0
        /// Set while nobody shows this analyser (`rest()`): the next buffer starts afresh.
        var resting = false
    }

    // MARK: Init (off the tap thread: it allocates)

    init(sampleRate: Double) {
        let rate = sampleRate > 0 ? sampleRate : 48000
        self.sampleRate = rate
        windowLength = Self.windowLength(sampleRate: rate)
        fftLength = 2 * windowLength
        log2FFTLength = vDSP_Length(fftLength.trailingZeroBitCount)
        hop = windowLength / 2
        guard let setup = vDSP_create_fftsetup(log2FFTLength, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed for 2^\(log2FFTLength) points")
        }
        fftSetup = setup
        frames = SpectrumTripleBuffer(count: SpectrumConstants.bandCount)
        layout = RealtimeBandLayout(Self.bandLayout(binHertz: rate / Double(fftLength), binCount: fftLength / 2))

        hann = Self.zeroed(windowLength)
        vDSP_hann_window(hann, vDSP_Length(windowLength), Int32(vDSP_HANN_DENORM))
        var windowSum: Float = 0
        vDSP_sve(hann, 1, &windowSum, vDSP_Length(windowLength))
        amplitudePerMagnitude = 1 / windowSum
        history = Self.zeroed(windowLength)
        windowed = Self.zeroed(fftLength)
        real = Self.zeroed(fftLength / 2)
        imaginary = Self.zeroed(fftLength / 2)
        power = Self.zeroed(fftLength / 2)
        bufferPeak = Self.zeroed(SpectrumConstants.bandCount)
        shown = Self.zeroed(SpectrumConstants.bandCount)
        tap = .allocate(capacity: 1)
        tap.initialize(to: TapState())
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        for buffer in [hann, history, windowed, real, imaginary, power, bufferPeak, shown] {
            buffer.deallocate()
        }
        tap.deallocate()
        layout.deallocate()
    }

    private static func zeroed(_ count: Int) -> UnsafeMutablePointer<Float> {
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        return buffer
    }

    /// The analysis window at `sampleRate`: the shipped 48 kHz window's length in time
    /// (`SpectrumConstants.windowSeconds`, 4096 frames), as the power of two that holds it.
    static func windowLength(sampleRate: Double) -> Int {
        let frames = max(2, Int((sampleRate * SpectrumConstants.windowSeconds).rounded()))
        return 1 << (Int.bitWidth - (frames - 1).leadingZeroBitCount)
    }

    // MARK: Tap thread

    /// The mixer tap: the mean of the first two channels (one channel if the buffer has one).
    /// Tap thread only. Real-time safe.
    func processTapBuffer(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: AVAudioFrameCount,
        channelCount: UInt32
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !buffers.isEmpty, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let right = channelCount >= 2 && buffers.count >= 2
            ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        analyse(left: left, right: right, count: Int(frameCount))
    }

    /// One channel (0 = L, 1 = R, …) of a non-interleaved buffer: Monitoring's per-channel taps.
    /// Tap thread only. Real-time safe.
    func processTapBuffer(
        _ bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: AVAudioFrameCount,
        channel: Int
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard channel >= 0, channel < buffers.count,
              let samples = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { return }
        analyse(left: samples, right: nil, count: Int(frameCount))
    }

    /// The tap runs but nobody shows this analyser (Monitoring is not on screen): skip the buffer.
    /// The first time, publish silence, so a view that comes back never shows the last frame; the
    /// next analysed buffer starts afresh, with no stale history or levels. Tap thread only.
    /// Real-time safe.
    func rest() {
        guard !tap.pointee.resting else { return }
        tap.pointee = TapState(resting: true)
        history.update(repeating: 0, count: windowLength)
        bufferPeak.update(repeating: 0, count: SpectrumConstants.bandCount)
        shown.update(repeating: 0, count: SpectrumConstants.bandCount)
        frames.write(UnsafeBufferPointer(start: shown, count: SpectrumConstants.bandCount))
    }

    /// Run `count` frames — `left`, or the mean of `left` and `right` — through the windows, then
    /// publish the buffer's frame.
    private func analyse(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, count: Int) {
        tap.pointee.resting = false
        var offset = 0
        while offset < count {
            let state = tap.pointee
            // Up to the next hop, and up to the ring's end.
            let take = min(count - offset, hop - state.sinceHop, windowLength - state.writeIndex)
            let destination = history + state.writeIndex
            if let right {
                var half: Float = 0.5
                vDSP_vasm(left + offset, 1, right + offset, 1, &half, destination, 1, vDSP_Length(take))
            } else {
                destination.update(from: left + offset, count: take)
            }
            offset += take
            tap.pointee.writeIndex = (state.writeIndex + take) % windowLength
            tap.pointee.sinceHop = state.sinceHop + take
            if tap.pointee.sinceHop == hop {
                tap.pointee.sinceHop = 0
                analyseWindow()
            }
        }
        tap.pointee.unpublishedSeconds += Double(count) / sampleRate
        publishIfAnalysed()
    }

    /// The latest `windowLength` samples: remove their mean, window them, transform, and fold each
    /// band's loudest amplitude into this buffer's peaks.
    private func analyseWindow() {
        let length = vDSP_Length(windowLength)
        // The ring, oldest sample first.
        let oldest = tap.pointee.writeIndex
        windowed.update(from: history + oldest, count: windowLength - oldest)
        (windowed + (windowLength - oldest)).update(from: history, count: oldest)
        var mean: Float = 0
        vDSP_meanv(windowed, 1, &mean, length)
        var negatedMean = -mean
        vDSP_vsadd(windowed, 1, &negatedMean, windowed, 1, length)
        vDSP_vmul(windowed, 1, hann, 1, windowed, 1, length)
        // windowed[windowLength...] stays zero: the ×2 padding.
        let halfLength = vDSP_Length(fftLength / 2)
        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: fftLength / 2) { pairs in
            vDSP_ctoz(pairs, 2, &split, 1, halfLength)
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2FFTLength, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, power, 1, halfLength) // bin 0 packs DC and Nyquist: no band reads it
        for band in 0 ..< SpectrumConstants.bandCount {
            let magnitude = layout.magnitude(of: band, in: power)
            bufferPeak[band] = max(bufferPeak[band], magnitude * amplitudePerMagnitude)
        }
        tap.pointee.windows += 1
    }

    /// After a buffer: if a window was analysed, turn the peaks into display levels through the
    /// ballistics and publish them.
    private func publishIfAnalysed() {
        guard tap.pointee.windows > 0 else { return }
        let floor = SpectrumConstants.noiseFloorDB
        let release = Float(exp(-tap.pointee.unpublishedSeconds / SpectrumConstants.releaseSeconds))
        for band in 0 ..< SpectrumConstants.bandCount {
            let decibels = 20 * log10f(max(bufferPeak[band], 1e-9))
            let level = min(max((decibels - floor) / -floor, 0), 1)
            shown[band] = max(level, release * shown[band])
            bufferPeak[band] = 0
        }
        tap.pointee.windows = 0
        tap.pointee.unpublishedSeconds = 0
        frames.write(UnsafeBufferPointer(start: shown, count: SpectrumConstants.bandCount))
    }

    // MARK: Band layout (off the tap thread)

    /// Where one band reads the spectrum.
    enum BandSpan: Equatable {
        /// The bins inside its span: their loudest.
        case bins(ClosedRange<Int>)
        /// Narrower than a bin: the spectrum at its centre, `position` bins up (interpolated).
        case centre(position: Double)
        /// Above Nyquist at this rate: nothing.
        case silent

        /// The bins it reads, if it reads bins.
        var bins: ClosedRange<Int>? {
            guard case let .bins(range) = self else { return nil }
            return range
        }

        /// Where it reads the spectrum, if it reads it at its centre.
        var centre: Double? {
            guard case let .centre(position) = self else { return nil }
            return position
        }
    }

    /// Each band's span over `binCount` bins `binHertz` apart. Band b spans
    /// [minHz·2^((b − ½)/6), minHz·2^((b + ½)/6)) — half a 1/6-octave step either side of its centre;
    /// a bin belongs to the band whose span holds its frequency, so no bin is in two bands, and bin 0
    /// (DC) is below every band.
    static func bandLayout(binHertz: Double, binCount: Int) -> [BandSpan] {
        let edges = (0 ... SpectrumConstants.bandCount).map { edge in
            Double(SpectrumConstants.minHz) * pow(2.0, (Double(edge) - 0.5) / 6.0)
        }
        return (0 ..< SpectrumConstants.bandCount).map { band in
            let first = max(1, Int((edges[band] / binHertz).rounded(.up)))
            let last = min(binCount - 1, Int((edges[band + 1] / binHertz).rounded(.up)) - 1)
            if first <= last {
                return .bins(first ... last)
            }
            let centre = Double(SpectrumConstants.bandCentreHz(Float(band))) / binHertz
            return centre + 1 < Double(binCount) ? .centre(position: centre) : .silent
        }
    }
}

// MARK: - The band layout, for the tap thread

/// `SpectrumAnalyzer.bandLayout` as raw arrays the tap thread reads without ARC: per band, a bin
/// range (`first...last`; empty when last < first) and an interpolation position (< 0: silent).
private struct RealtimeBandLayout {
    private let first: UnsafeMutablePointer<Int>
    private let last: UnsafeMutablePointer<Int>
    private let centre: UnsafeMutablePointer<Float>

    init(_ spans: [SpectrumAnalyzer.BandSpan]) {
        first = .allocate(capacity: spans.count)
        last = .allocate(capacity: spans.count)
        centre = .allocate(capacity: spans.count)
        for (band, span) in spans.enumerated() {
            // An empty range (1...0) for a band read at its centre, and for a silent one.
            (first + band).initialize(to: span.bins?.lowerBound ?? 1)
            (last + band).initialize(to: span.bins?.upperBound ?? 0)
            (centre + band).initialize(to: span.centre.map(Float.init) ?? -1)
        }
    }

    /// The owner's `deinit` frees the arrays (a struct has no `deinit`).
    func deallocate() {
        first.deallocate()
        last.deallocate()
        centre.deallocate()
    }

    /// Band `band`'s FFT magnitude, from `power` (|X|² per bin). Real-time safe.
    func magnitude(of band: Int, in power: UnsafePointer<Float>) -> Float {
        if first[band] <= last[band] {
            var loudest: Float = 0
            vDSP_maxv(power + first[band], 1, &loudest, vDSP_Length(last[band] - first[band] + 1))
            return sqrtf(loudest)
        }
        let position = centre[band]
        guard position >= 0 else { return 0 }
        let below = Int(position)
        let fraction = position - Float(below)
        return sqrtf(power[below]) * (1 - fraction) + sqrtf(power[below + 1]) * fraction
    }
}
