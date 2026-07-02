import Foundation

// MARK: - CrossfeedStrength

/// User-facing crossfeed strength levels, mapping to the bs2b coefficient sets
/// in the C++ DSP kernel.
///
/// - Relaxed: subtlest, fc = 650 Hz, −9.5 dB cross level (bs2b "Jmeier").
/// - defaultStrength: Bauer original, fc = 700 Hz, −9.0 dB (the safe default).
/// - strong: most spacious, fc = 700 Hz, −6.0 dB (bs2b "Cmoy").
///
/// The C++ enum uses `CrossfeedPreset::Bauer` (= 1) for what the user sees as
/// "Default" (§5 F8: avoids the `default:` keyword clash in C++ switch statements).
enum CrossfeedStrength: Int, CaseIterable, Identifiable {
    case relaxed = 0
    case defaultStrength = 1
    case strong = 2

    var id: Int {
        rawValue
    }

    /// Display label shown in the UI Picker.
    var displayName: String {
        switch self {
        case .relaxed: "Relaxed"
        case .defaultStrength: "Default"
        case .strong: "Strong"
        }
    }

    /// Crossfeed level in [0, 1] forwarded to `publishCrossfeed`.
    /// Maps each strength to a normalised level derived from the bs2b cross-level values.
    var dspLevel: Float {
        switch self {
        case .relaxed: 0.335 // α ≈ 0.335  (−9.5 dB)
        case .defaultStrength: 0.355 // α ≈ 0.355  (−9.0 dB)
        case .strong: 0.501 // α ≈ 0.501  (−6.0 dB)
        }
    }

    /// Raw preset index sent to the C-ABI. Matches `CrossfeedPreset` (Relaxed=0, Bauer=1, Strong=2).
    var presetIndex: UInt32 {
        UInt32(rawValue)
    }
}
