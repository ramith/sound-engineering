// Spectrum.swift — spectral-analysis helpers for SRCQualityMeasure.
//
// Windowing, real-FFT power spectrum, lobe/spur power extraction, and dB conversion. Split out of
// main.swift so each file stays within the swiftlint file-length budget. Module-internal (not
// file-private) so main.swift can call them.

import Accelerate
import Foundation

// MARK: - Spectral analysis

// 4-term Blackman-Harris window coefficients (a0..a3) from Harris (1978),
// "On the Use of Windows for Harmonic Analysis with the DFT", Table 1.
// Peak side-lobe ~ -92 dB. The alternating-sign cosine sum is:
//   w(n) = a0 - a1*cos(φ) + a2*cos(2φ) - a3*cos(3φ),  φ = 2π·n/(N-1).
private let kBhA0: Double = 0.35875
private let kBhA1: Double = 0.48829
private let kBhA2: Double = 0.14128
private let kBhA3: Double = 0.01168

/// 4-term Blackman-Harris window (peak side-lobe ~ -92 dB), built into `window`. A low-side-lobe
/// window is essential here: it pushes the analysis window's own spectral skirt of the (off-bin)
/// signal below the -80 dB aliasing floor, so what is left to measure is genuine converter
/// aliasing, not measurement leakage. (vDSP's Hann/Blackman side-lobes are too high for an -80 dB
/// floor.)
func blackmanHarris(_ window: inout [Double], _ size: Int) {
    let denom = Double(size - 1)
    for index in 0 ..< size {
        let phase = 2.0 * Double.pi * Double(index) / denom
        window[index] = kBhA0 - kBhA1 * cos(phase)
            + kBhA2 * cos(2.0 * phase) - kBhA3 * cos(3.0 * phase)
    }
}

/// One real-FFT power spectrum of `signal` windowed with a 4-term Blackman-Harris window. Returns
/// `fftSize/2 + 1` power values (DC..Nyquist), each a normalised single-sided amplitude squared
/// (divided by the window's coherent gain so a sine's main-lobe peak recovers its true amplitude).
/// `signal` must hold at least `fftSize` samples starting at `offset`.
func powerSpectrum(_ signal: [Float], offset: Int, fftSize: Int) -> [Double]? {
    guard offset >= 0, offset + fftSize <= signal.count else { return nil }
    let log2n = vDSP_Length(log2(Double(fftSize)).rounded())
    guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return nil }
    defer { vDSP_destroy_fftsetupD(setup) }

    // Low-side-lobe analysis window (double precision for clean spur floors).
    var window = [Double](repeating: 0, count: fftSize)
    blackmanHarris(&window, fftSize)

    // Windowed, double-precision copy of the analysis frame.
    var windowed = [Double](repeating: 0, count: fftSize)
    for index in 0 ..< fftSize {
        windowed[index] = Double(signal[offset + index]) * window[index]
    }

    // Coherent gain of the window: sum(w)/N. A sine of amplitude A windowed by it has its spectral
    // main-lobe peak recover to A after dividing the amplitude by this gain.
    var windowSum: Double = 0
    vDSP_sveD(&window, 1, &windowSum, vDSP_Length(fftSize))
    let coherentGain = windowSum / Double(fftSize)
    guard coherentGain > 0 else { return nil }

    let halfN = fftSize / 2
    var real = [Double](repeating: 0, count: halfN)
    var imag = [Double](repeating: 0, count: halfN)
    var power = [Double](repeating: 0, count: halfN + 1)

    windowed.withUnsafeMutableBufferPointer { wPtr in
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                guard
                    let wBase = wPtr.baseAddress,
                    let rBase = rPtr.baseAddress,
                    let iBase = iPtr.baseAddress
                else { return }
                var split = DSPDoubleSplitComplex(realp: rBase, imagp: iBase)
                wBase.withMemoryRebound(to: DSPDoubleComplex.self, capacity: halfN) { cPtr in
                    vDSP_ctozD(cPtr, 2, &split, 1, vDSP_Length(halfN))
                }
                vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                // vDSP_fft_zripD stores results with an implicit factor-of-2 relative to the ideal
                // DFT, and packs the Nyquist bin into imag[0]. For the single-sided spectrum:
                //   Interior bins (1..N/2-1): true amplitude = |zrip| / N   (the factor-of-2
                //     from the vDSP convention and the factor-of-2 from single-siding cancel).
                //   DC and Nyquist (bin 0 and N/2): these bins are NOT doubled for single-siding,
                //     so they need an extra /2 on top of the /N factor.
                // Dividing by coherentGain normalises so an on-bin sine of amplitude A reads A.
                let interiorScale = (1.0 / Double(fftSize)) / coherentGain
                // DC/Nyquist are one-sided (not doubled), so their amplitude is half the interior.
                let edgeScale = interiorScale / 2.0
                let dcAmp = abs(rBase[0]) * edgeScale // DC (bin 0): real only, not doubled
                power[0] = dcAmp * dcAmp
                let nyqAmp = abs(iBase[0]) * edgeScale // Nyquist in imag[0], not doubled
                power[halfN] = nyqAmp * nyqAmp
                for bin in 1 ..< halfN {
                    let amp =
                        sqrt(rBase[bin] * rBase[bin] + iBase[bin] * iBase[bin]) * interiorScale
                    power[bin] = amp * amp
                }
            }
        }
    }
    return power
}

/// PEAK bin power within the main lobe centred on `bin` (+- `lobeHalfWidthBins`), clamped to the
/// spectrum bounds. Using the lobe PEAK (not the lobe sum) recovers the tone/spur amplitude without
/// the lobe-width inflation a power sum would add for an off-bin (scalloped, leakage-spread) tone.
/// Signal, image, and aliasing are ALL measured this way, so their ratios are scale-consistent.
func lobePeakPower(_ power: [Double], centerBin: Int) -> Double {
    let loBin = max(0, centerBin - Measure.lobeHalfWidthBins)
    let hiBin = min(power.count - 1, centerBin + Measure.lobeHalfWidthBins)
    guard hiBin >= loBin else { return 0 }
    var peak: Double = 0
    for bin in loBin ... hiBin {
        peak = max(peak, power[bin])
    }
    return peak
}

/// Worst spurious bin power in `[loBin, hiBin]` excluding any bin within `excludeRadius` of an
/// excluded center. Each spur is the single-bin peak (directly comparable to the signal's lobe
/// peak). Returns the worst spur power found.
func worstSpurPower(
    _ power: [Double],
    loBin: Int,
    hiBin: Int,
    excludeCenters: [Int],
    excludeRadius: Int
) -> Double {
    let scanLo = max(1, loBin)
    let scanHi = min(power.count - 1, hiBin)
    guard scanHi >= scanLo else { return 0 }
    var worst: Double = 0
    for bin in scanLo ... scanHi {
        var excluded = false
        for center in excludeCenters where abs(bin - center) <= excludeRadius {
            excluded = true
            break
        }
        if excluded { continue }
        worst = max(worst, power[bin])
    }
    return worst
}

/// Nearest FFT bin to `freqHz` for an FFT of `fftSize` over a signal at `rate`.
func binForFrequency(_ freqHz: Double, rate: Double, fftSize: Int) -> Int {
    Int((freqHz / rate * Double(fftSize)).rounded())
}

/// Linear power ratio -> dB, floored so a clean spur reads a finite very-low number, never -inf.
func powerRatioToDb(_ ratio: Double) -> Double {
    let safe = max(ratio, Measure.powerFloor)
    let decibels = 10.0 * log10(safe)
    return decibels.isFinite ? decibels : -200.0
}
