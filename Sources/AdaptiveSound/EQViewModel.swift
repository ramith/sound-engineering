import Combine
import Foundation

// MARK: - EQ Preset Definition (Internal)

/// Hardcoded EQ preset definitions for audio enhancement
private struct EQPresetDefinition {
    let name: String
    let gains: [Float] // 31 bands, -20 to +12 dB range

    /// Flat preset: all bands at 0 dB (passthrough)
    static let flat = EQPresetDefinition(
        name: "Flat",
        gains: [Float](repeating: 0.0, count: 31)
    )

    /// Presence preset: noticeably boosts 2–5 kHz for clarity
    /// ISO 266 1/3-octave bands: [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
    ///                            200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
    ///                            2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
    /// Boosts at 1600 Hz (band 19), 2000 Hz (20), 2500 Hz (21), 3150 Hz (22), 4000 Hz (23), 5000 Hz (24)
    static let presence = EQPresetDefinition(
        name: "Presence",
        gains: [
            0.0, // 20 Hz
            0.0, // 25 Hz
            0.0, // 31.5 Hz
            0.0, // 40 Hz
            0.0, // 50 Hz
            0.0, // 63 Hz
            0.0, // 80 Hz
            0.0, // 100 Hz
            0.0, // 125 Hz
            0.0, // 160 Hz
            0.0, // 200 Hz
            0.0, // 250 Hz
            0.0, // 315 Hz
            0.0, // 400 Hz
            0.0, // 500 Hz
            0.0, // 630 Hz
            0.0, // 800 Hz
            0.0, // 1000 Hz
            0.0, // 1250 Hz
            2.5, // 1600 Hz - subtle boost
            4.0, // 2000 Hz - notable presence
            5.0, // 2500 Hz - peak presence
            4.5, // 3150 Hz - sustain presence
            3.5, // 4000 Hz - natural falloff
            2.0, // 5000 Hz - gentle tail
            0.0, // 6300 Hz
            -1.0, // 8000 Hz - slight de-ess
            0.0, // 10000 Hz
            0.0, // 12500 Hz
            0.0, // 16000 Hz
            0.0, // 20000 Hz
        ]
    )

    /// Clarity preset: emphasis on detail and articulation (1–8 kHz region)
    static let clarity = EQPresetDefinition(
        name: "Clarity",
        gains: [
            0.0, // 20 Hz
            0.0, // 25 Hz
            0.0, // 31.5 Hz
            0.0, // 40 Hz
            0.0, // 50 Hz
            0.0, // 63 Hz
            0.0, // 80 Hz
            -1.0, // 100 Hz - very slight low-cut
            0.0, // 125 Hz
            0.0, // 160 Hz
            0.0, // 200 Hz
            0.0, // 250 Hz
            0.5, // 315 Hz - gentle mid-lift
            1.0, // 400 Hz
            1.5, // 500 Hz - core clarity
            2.0, // 630 Hz
            2.5, // 800 Hz - pronounced clarity
            3.0, // 1000 Hz - peak clarity
            3.0, // 1250 Hz - sustain clarity
            2.5, // 1600 Hz
            2.0, // 2000 Hz - detail emphasis
            1.5, // 2500 Hz
            1.0, // 3150 Hz
            1.5, // 4000 Hz - definition
            1.0, // 5000 Hz
            0.5, // 6300 Hz
            0.0, // 8000 Hz
            0.0, // 10000 Hz
            0.0, // 12500 Hz
            0.0, // 16000 Hz
            0.0, // 20000 Hz
        ]
    )

    /// Warm preset: bass-heavy, rolled-off highs for smooth, mellow tone
    static let warm = EQPresetDefinition(
        name: "Warm",
        gains: [
            0.0, // 20 Hz
            0.5, // 25 Hz - subtle sub-bass lift
            1.5, // 31.5 Hz
            2.0, // 40 Hz
            2.5, // 50 Hz - pronounced bass
            2.0, // 63 Hz - warm low-mids
            1.5, // 80 Hz
            1.0, // 100 Hz - full bass envelope
            0.5, // 125 Hz
            0.0, // 160 Hz
            -0.5, // 200 Hz - slight scoop
            -0.5, // 250 Hz
            0.0, // 315 Hz
            0.0, // 400 Hz
            0.5, // 500 Hz - warm mid-bass
            1.0, // 630 Hz - tone warmth
            0.5, // 800 Hz
            0.0, // 1000 Hz - neutral presence
            -0.5, // 1250 Hz
            -1.0, // 1600 Hz - slight presence dip
            -1.5, // 2000 Hz - rolled-off presence
            -2.0, // 2500 Hz - smooth treble
            -2.0, // 3150 Hz
            -1.5, // 4000 Hz
            -1.0, // 5000 Hz - gentle treble roll
            -0.5, // 6300 Hz
            0.0, // 8000 Hz
            0.0, // 10000 Hz
            0.0, // 12500 Hz
            0.0, // 16000 Hz
            0.0, // 20000 Hz
        ]
    )

    /// All available presets
    static let all: [EQPresetDefinition] = [.flat, .presence, .clarity, .warm]
}

// MARK: - EQViewModel

/// Manages 31-band parametric EQ state and preset selection
///
/// This ViewModel maintains the user-facing EQ parameters and dispatches
/// changes to the audio engine via AudioViewModel's parameter bus.
/// Presets are hardcoded; ML-based genre detection is deferred to Phase 1.5.
@MainActor
final class EQViewModel: ObservableObject {
    /// Individual band gains (dB), indexed 0–30 for ISO 266 1/3-octave bands
    /// Range: -20 to +12 dB per band
    @Published var bandGains: [Float] = .init(repeating: 0.0, count: 31)

    /// Currently selected preset name (Flat, Presence, Clarity, Warm)
    @Published var selectedPreset: String = "Flat"

    /// Frequency response magnitude for UI graphing (31-point curve)
    /// Values in dB relative to flat (0 dB baseline)
    @Published var frequencyResponse: [Float] = .init(repeating: 0.0, count: 31)

    /// Reference to the audio engine for parameter dispatch
    private let audioViewModel: AudioViewModel

    /// Parameter IDs for EQ band dispatch (IDs 100–130 reserved for EQ bands)
    private let eqBandBaseParameterID: UInt32 = 100

    init(audioViewModel: AudioViewModel) {
        self.audioViewModel = audioViewModel

        // Initialize to Flat preset
        bandGains = EQPresetDefinition.flat.gains
        frequencyResponse = EQPresetDefinition.flat.gains
    }

    // MARK: - Preset Management

    /// Select a preset and apply its gains to all bands
    /// - Parameter name: Preset name (Flat, Presence, Clarity, Warm)
    func selectPreset(_ name: String) {
        guard let preset = EQPresetDefinition.all.first(where: { $0.name == name }) else {
            return
        }

        selectedPreset = name
        bandGains = preset.gains
        frequencyResponse = preset.gains

        // Dispatch all band gains to audio engine
        for (index, gain) in preset.gains.enumerated() {
            applyBandGain(index, gain)
        }
    }

    // MARK: - Parameter Dispatch

    /// Apply a gain change to a specific EQ band
    /// - Parameter index: Band index (0–30)
    /// - Parameter gain: Gain in dB (-20 to +12)
    func applyBandGain(_ index: Int, _ gain: Float) {
        // Clamp gain to valid range
        let clampedGain = max(-20.0, min(12.0, gain))

        // Update local state
        if index >= 0, index < bandGains.count {
            bandGains[index] = clampedGain
            frequencyResponse[index] = clampedGain
        }

        // Mark that current preset is custom (no longer matches a named preset)
        selectedPreset = "Custom"

        // Dispatch to audio engine via parameter bus
        let paramID = eqBandBaseParameterID + UInt32(index)
        audioViewModel.setParameter(paramID, value: clampedGain)
    }

    // MARK: - Utility Methods

    /// Reset all bands to flat (0 dB)
    func resetToFlat() {
        selectPreset("Flat")
    }

    /// Get the name of the currently selected preset
    var presetName: String {
        selectedPreset
    }

    /// Available preset names for UI dropdown
    var availablePresets: [String] {
        EQPresetDefinition.all.map { $0.name }
    }
}
