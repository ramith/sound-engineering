import Foundation
import SettingsKit

// MARK: - CrossfeedStrength

/// What each crossfeed strength shows and plays. The values themselves are a setting (`SettingsKit`).
///
/// Each strength is one of bs2b's own levels (libbs2b `bs2b.h`; council C-42), played at full
/// strength by the DSP kernel's crossfeed:
/// - Relaxed: the subtlest — bs2b "Jmeier", 650 Hz cut, 9.5 dB feed.
/// - Default: bs2b "Cmoy", 700 Hz, 6.0 dB.
/// - Strong: the most spacious — bs2b's own default level, 700 Hz, 4.5 dB.
///
/// The C++ kernel names the presets after those levels (`CrossfeedPreset::Jmeier` / `Cmoy` /
/// `Bs2bDefault`); the index is the shared contract.
extension CrossfeedStrength {
    /// Display label shown in the UI Picker.
    var displayName: String {
        switch self {
        case .relaxed: "Relaxed"
        case .defaultStrength: "Default"
        case .strong: "Strong"
        }
    }

    /// Raw preset index sent to the C-ABI. Matches `CrossfeedPreset` (Jmeier = 0, Cmoy = 1,
    /// Bs2bDefault = 2).
    var presetIndex: UInt32 {
        UInt32(rawValue)
    }
}
