import Foundation

// MARK: - Spectrum Constants

enum SpectrumConstants {
    static let fftSize: Int = 4096
    static let bandCount: Int = 44
    static let displayBarCount: Int = 88 // 2 bars per band; view interpolates
    static let minHz: Float = 40.0
    static let maxHz: Float = 20000.0
    static let noiseFloorDB: Float = -80.0 // dB floor mapped to 0.0
    static let releaseAlpha: Float = 0.85 // IIR release coefficient (~150 ms @ 20 Hz)
}
