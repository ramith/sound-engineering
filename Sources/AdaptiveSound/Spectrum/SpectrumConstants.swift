import Foundation

// MARK: - Spectrum Constants

enum SpectrumConstants {
    /// The frames each analysis tap asks for. AVAudioEngine delivers at least 100 ms whatever is asked
    /// (Apple's floor: 4410 at 44.1 kHz, 19 200 at 192 kHz); the analyser takes every one.
    static let tapBufferFrames: Int = 4096
    /// The analysis window's length in time: the shipped 4096 frames at 48 kHz (85.3 ms). The analyser
    /// keeps it at every rate (`SpectrumAnalyzer.windowLength`), so its bins are ≈ 11 Hz apart at all.
    static let windowSeconds: Double = 4096.0 / 48000.0
    static let bandCount: Int = 44
    static let displayBarCount: Int = 88 // 2 bars per band; view interpolates
    /// The lowest band's centre. The 44 bands climb in 1/6-octave steps from here, so the highest sits
    /// near 5.7 kHz (`bandCentreHz(43)`) — the analyzer shows no band above that.
    static let minHz: Float = 40.0
    static let noiseFloorDB: Float = -80.0 // dB floor mapped to 0.0
    /// The bars' release time constant: y = max(x, e^(−Δt/τ)·y) per frame. The shipped 0.85 per 100 ms
    /// tap buffer (τ = 0.1 s / ln(1/0.85)), now per second of audio, whatever buffer size the tap gets.
    static let releaseSeconds: Double = 0.1 / log(1 / 0.85)

    /// The centre (Hz) of analyzer band `band` — fractional for the display bars between two bands:
    /// 1/6-octave steps up from `minHz`. The analyzer's bins and the EQ graph's silhouette both place
    /// bands by this one formula.
    static func bandCentreHz(_ band: Float) -> Float {
        minHz * powf(2.0, band / 6.0)
    }

    /// The centre (Hz) of display bar `bar` of `barCount` (the 44 bands upsampled, `spectrumBars`).
    static func barCentreHz(_ bar: Int, of barCount: Int = displayBarCount) -> Float {
        bandCentreHz(barCount > 1 ? Float(bar) / Float(barCount - 1) * Float(bandCount - 1) : 0)
    }
}
