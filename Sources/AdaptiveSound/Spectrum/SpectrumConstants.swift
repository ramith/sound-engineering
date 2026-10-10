import Foundation

// MARK: - Spectrum Constants

enum SpectrumConstants {
    static let fftSize: Int = 4096
    static let bandCount: Int = 44
    static let displayBarCount: Int = 88 // 2 bars per band; view interpolates
    /// The lowest band's centre. The 44 bands climb in 1/6-octave steps from here, so the highest sits
    /// near 5.7 kHz (`bandCentreHz(43)`) — the analyzer shows no band above that.
    static let minHz: Float = 40.0
    static let noiseFloorDB: Float = -80.0 // dB floor mapped to 0.0
    static let releaseAlpha: Float = 0.85 // IIR release coefficient (~150 ms @ 20 Hz)

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
