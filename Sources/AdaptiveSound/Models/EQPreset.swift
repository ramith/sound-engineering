import Foundation

// MARK: - EQ Preset

/// Canonical 31-band EQ preset definitions.
///
/// This is the single source of truth for all preset shapes. Both the UI
/// canvas and the DSP dispatch path read from this enum; no other file should
/// define preset gains.
///
/// Band ordering follows ISO 266 1/3-octave centres:
/// 20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
/// 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
/// 10000, 12500, 16000, 20000 Hz
enum EQPreset: String, CaseIterable, Identifiable {
    case flat = "Flat"
    case presence = "Presence"
    case clarity = "Clarity"
    case warm = "Warm"

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue
    }

    // MARK: - Canonical Gains (Float for DSP dispatch)

    /// Canonical 31-band gain array (dB). Derived from the trig formulas that
    /// were already in `FrequencyResponseCanvas` — evaluated once at the ISO
    /// 1/3-octave centres and stored so the DSP kernel gets deterministic values.
    var gains: [Float] {
        switch self {
        case .flat:
            return [Float](repeating: 0.0, count: 31)

        case .presence:
            // Bell centred around 2 kHz: peaks at ~8 dB at 2 kHz, decays to
            // ~4 dB at 8 kHz, 0 below 1 kHz.
            // Formula: gainForPresence() from FrequencyResponseCanvas, evaluated
            // at each ISO centre frequency.
            return Self.isoFrequencies.map { Float(gainForPresence($0)) }

        case .clarity:
            // Rising shelf from 1 kHz to 8 kHz (+6 dB), then rolls off toward
            // 16 kHz (+4 dB), 0 below 1 kHz.
            return Self.isoFrequencies.map { Float(gainForClarity($0)) }

        case .warm:
            // Bass shelf peaking below 500 Hz, decaying through 2 kHz.
            return Self.isoFrequencies.map { Float(gainForWarm($0)) }
        }
    }

    // MARK: - Gains as Double (for FrequencyResponseCanvas drawing)

    /// Same gains as `Double` for use by the canvas interpolation code.
    var gainsAsDouble: [Double] {
        gains.map { Double($0) }
    }

    // MARK: - ISO Centre Frequencies

    static let isoFrequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
        2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
    ]
}

// MARK: - Private gain formulas (namespace-scoped)

/// These functions are the canonical trig formulas. They live here so only
/// this file owns the shape of each preset.
private func gainForPresence(_ freq: Double) -> Double {
    if freq >= 1000 && freq <= 4000 {
        8.0 * sin((log10(freq) - log10(1000)) / (log10(4000) - log10(1000)) * .pi)
    } else if freq > 4000 && freq <= 8000 {
        4.0 * sin((log10(8000) - log10(freq)) / (log10(8000) - log10(4000)) * .pi / 2)
    } else {
        0.0
    }
}

private func gainForClarity(_ freq: Double) -> Double {
    if freq >= 1000 && freq <= 8000 {
        6.0 * sin((log10(freq) - log10(1000)) / (log10(8000) - log10(1000)) * .pi / 2)
    } else if freq > 8000 && freq <= 16000 {
        4.0 * sin((log10(16000) - log10(freq)) / (log10(16000) - log10(8000)) * .pi / 2)
    } else {
        0.0
    }
}

private func gainForWarm(_ freq: Double) -> Double {
    if freq >= 20 && freq <= 500 {
        12.0 * (1.0 - exp(-log10(freq) / 1.5))
    } else if freq > 500 && freq <= 2000 {
        8.0 * exp(-(freq - 500) / 1500)
    } else {
        0.0
    }
}
