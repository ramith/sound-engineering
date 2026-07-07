import Foundation

// MARK: - EQ Live State

/// Persisted snapshot of the *currently active* EQ so the app can restore the
/// user's last EQ setting on launch ("remember last setting").
///
/// Persistence lives in `EQViewModel+Persistence.swift` under the versioned key
/// `"eqLiveStateV1"` (JSON blob, tolerant decode) — mirroring the existing custom-preset
/// and device-map persistence pattern.
///
/// - `presetRaw`: the active `EQPreset.rawValue`, or `nil` when the user has custom edits
///   (`selectedPreset == nil`, i.e. "Custom").
/// - `bandGains`: the 31-band gain vector (dB). Validated to exactly 31 bands and clamped
///   to the DSP range `[-12, +12]` on restore (defense-in-depth, matching
///   `commitCustomBandEdits`).
struct EQLiveState: Codable {
    var presetRaw: String?
    var bandGains: [Float]
}
