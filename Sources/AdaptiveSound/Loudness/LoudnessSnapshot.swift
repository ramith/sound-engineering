import Foundation

/// A point-in-time loudness readout for the UI meters, produced off the audio
/// thread by the BS.1770-5 `LufsMeter` (via the C bridge) and polled by the view
/// model. All values are LUFS except `peakDb` (sample-peak dBFS).
struct LoudnessSnapshot: Equatable {
    var integratedLufs: Double
    var shortTermLufs: Double
    var momentaryLufs: Double
    var peakDb: Double

    /// Sentinel before any measurement exists (engine stopped / silence).
    static let unmeasured = LoudnessSnapshot(
        integratedLufs: -200, shortTermLufs: -200, momentaryLufs: -200, peakDb: -120
    )

    /// True once the meter has produced a real integrated value.
    var hasSignal: Bool {
        integratedLufs > -100
    }
}
