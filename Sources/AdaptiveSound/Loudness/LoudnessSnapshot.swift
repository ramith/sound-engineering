import Foundation

/// A point-in-time loudness readout for the UI meters, produced off the audio
/// thread by the BS.1770-5 `LufsMeter` (via the C bridge) and polled by the view
/// model. All values are LUFS except `truePeakDb` — inter-sample TRUE peak in
/// dBTP (8× polyphase ISP, the shared `TruePeakKernel`; sample-peak before
/// S10.8 PR E — the "True peak" meter label is honest because of this field).
struct LoudnessSnapshot: Equatable {
    var integratedLufs: Double
    var shortTermLufs: Double
    var truePeakDb: Double

    /// Sentinel before any measurement exists (engine stopped / silence).
    static let unmeasured = LoudnessSnapshot(
        integratedLufs: -200, shortTermLufs: -200, truePeakDb: -120
    )

    /// True once the meter has produced a real integrated value.
    var hasSignal: Bool {
        integratedLufs > -100
    }
}
