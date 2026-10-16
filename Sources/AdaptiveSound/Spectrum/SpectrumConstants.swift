import Foundation

// MARK: - Spectrum Constants

enum SpectrumConstants {
    /// The frames each analysis tap asks for. The engine's tap delivers at least 100 ms whatever is asked
    /// (Apple's floor: 4410 at 44.1 kHz, 19 200 at 192 kHz); the analyser takes every one.
    static let tapBufferFrames: Int = 4096
    /// The analysis window's length in time: the shipped 4096 frames at 48 kHz (85.3 ms). The analyser
    /// keeps it at every rate (`SpectrumAnalyzer.windowLength`), so its bins are ≈ 11 Hz apart at all.
    static let windowSeconds: Double = 4096.0 / 48000.0
    static let bandCount: Int = 44
    static let displayBarCount: Int = 88 // 2 bars per band; view interpolates
    /// The analyser's range: its 44 bands tile 20 Hz – 20 kHz, the audible range, in equal log steps —
    /// each a 44th of three decades, ≈ 0.23 octave — so the lens's "20 Hz – 20 kHz" axis is true and the
    /// treble shows (founder decision 2026-10-16). Before: 1/6-octave bands from 37.8 Hz to 6.05 kHz.
    static let lowestHz: Double = 20
    static let highestHz: Double = 20000
    static let noiseFloorDB: Float = -80.0 // dB floor mapped to 0.0
    /// The bars' release time constant: y = max(x, e^(−Δt/τ)·y) per frame. The shipped 0.85 per 100 ms
    /// tap buffer (τ = 0.1 s / ln(1/0.85)), now per second of audio, whatever buffer size the tap gets.
    static let releaseSeconds: Double = 0.1 / log(1 / 0.85)

    /// Band edge `edge` in Hz, 0…`bandCount`: band b spans [edge b, edge b + 1). Edge 0 is 20 Hz and the
    /// last is 20 kHz. The analyser's bins and every view that places a band by frequency read this.
    static func bandEdgeHz(_ edge: Int) -> Double {
        lowestHz * pow(highestHz / lowestHz, Double(edge) / Double(bandCount))
    }

    /// The centre (Hz) of analyzer band `band` — its edges' geometric mean; fractional for the display
    /// bars between two bands. The EQ graph's silhouette places bars by it.
    static func bandCentreHz(_ band: Float) -> Float {
        Float(lowestHz * pow(highestHz / lowestHz, (Double(band) + 0.5) / Double(bandCount)))
    }

    /// The centre (Hz) of display bar `bar` of `barCount` (the 44 bands upsampled, `SpectrumSampler`).
    static func barCentreHz(_ bar: Int, of barCount: Int = displayBarCount) -> Float {
        bandCentreHz(barCount > 1 ? Float(bar) / Float(barCount - 1) * Float(bandCount - 1) : 0)
    }
}
