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
///
/// Menu order (F6): analytic group first (flat/presence/clarity/warm), then
/// house curves (loudness/vocal/studio), then Custom (shown via a Divider in
/// the picker — not a case here).
enum EQPreset: String, CaseIterable, Identifiable {
    // MARK: Analytic group

    case flat = "Flat"
    case presence = "Presence"
    case clarity = "Clarity"
    case warm = "Warm"

    // MARK: House curves

    /// Gentle bass + treble lift, inspired by the equal-loudness contours
    /// (Fletcher-Munson). Compensates for reduced sensitivity at low and high
    /// frequencies at moderate listening levels.
    case loudness = "Loudness"

    /// Upper-midrange presence push centred around 3 kHz. Brings vocal and
    /// acoustic-instrument detail forward without harshness above 8 kHz.
    case vocal = "Vocal"

    /// Near-flat reference with a subtle high-frequency air shelf (above 8 kHz).
    /// Emulates the slight top-end lift of flat-response studio monitors in
    /// a treated room without colouring the midrange.
    case studio = "Studio"

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
            // Matches gainForPresence: main bell over 1–4 kHz peaking ~+8 dB at 2 kHz (0 at 4 kHz),
            // then a smaller lobe peaking ~+4 dB at 4 kHz that decays to 0 by 8 kHz; 0 below 1 kHz.
            return Self.isoFrequencies.map { Float(gainForPresence($0)) }

        case .clarity:
            // Matches gainForClarity: rising shelf 1 kHz → 8 kHz reaching +6 dB at 8 kHz, then a
            // +4 dB lobe just above 8 kHz that rolls off to 0 by 16 kHz; 0 below 1 kHz.
            return Self.isoFrequencies.map { Float(gainForClarity($0)) }

        case .warm:
            // Matches gainForWarm: low-mid lift rising from ~+7 dB at 20 Hz to ~+10 dB at 500 Hz,
            // then decaying from ~+8 dB just above 500 Hz through ~+3 dB at 2 kHz; 0 above 2 kHz.
            return Self.isoFrequencies.map { Float(gainForWarm($0)) }

        case .loudness:
            // Gentle bass lift (peaks ~+4 dB at 20–40 Hz, decays to 0 at 500 Hz)
            // plus a moderate treble lift (+1.5 dB at 5 kHz, +3 dB at 12.5–20 kHz).
            return Self.isoFrequencies.map { Float(gainForLoudness($0)) }

        case .vocal:
            // Bell centred at 3.15 kHz, +6 dB peak, 2.5-octave width.
            // Tapers to 0 below 500 Hz and above 8 kHz.
            return Self.isoFrequencies.map { Float(gainForVocal($0)) }

        case .studio:
            // Near-flat + air shelf: 0 dB below 8 kHz, gentle +2 dB shelf
            // at 16 kHz and above, with a smooth transition.
            return Self.isoFrequencies.map { Float(gainForStudio($0)) }
        }
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

/// Loudness: equal-loudness-inspired bass + treble lift.
/// Bass shelf: +4 dB peak at 20–40 Hz, decays to 0 dB at 500 Hz via a cosine ramp.
/// Treble shelf: smooth rise from 0 dB at 3.15 kHz to +3 dB at 12.5 kHz and above.
private func gainForLoudness(_ freq: Double) -> Double {
    // Bass component (20–500 Hz): half-cosine from +4 dB at 20 Hz to 0 dB at 500 Hz
    let bassGain: Double
    if freq <= 500 {
        let norm = (log10(freq) - log10(20)) / (log10(500) - log10(20))
        bassGain = 4.0 * cos(norm * .pi / 2)
    } else {
        bassGain = 0.0
    }

    // Treble component (3.15 kHz–20 kHz): half-sine rise from 0 to +3 dB
    let trebleGain: Double
    if freq >= 3150 {
        let norm = min(1.0, (log10(freq) - log10(3150)) / (log10(12500) - log10(3150)))
        trebleGain = 3.0 * sin(norm * .pi / 2)
    } else {
        trebleGain = 0.0
    }

    return bassGain + trebleGain
}

/// Vocal: bell centred at 3.15 kHz (+6 dB), 2.5-octave width.
/// Tapers to 0 below 500 Hz and above 8 kHz using half-sine ramps.
private func gainForVocal(_ freq: Double) -> Double {
    // Full bell region: 500 Hz to 8 kHz, peak at 3.15 kHz
    if freq >= 500 && freq <= 3150 {
        // Rising half-sine: 0 at 500 Hz, 1 at 3150 Hz
        let norm = (log10(freq) - log10(500)) / (log10(3150) - log10(500))
        return 6.0 * sin(norm * .pi / 2)
    } else if freq > 3150 && freq <= 8000 {
        // Falling half-sine: 1 at 3150 Hz, 0 at 8 kHz
        let norm = (log10(8000) - log10(freq)) / (log10(8000) - log10(3150))
        return 6.0 * sin(norm * .pi / 2)
    } else {
        return 0.0
    }
}

/// Studio: near-flat reference + air shelf above 8 kHz.
/// 0 dB at and below 8 kHz; rises to +2 dB at 16 kHz and above.
private func gainForStudio(_ freq: Double) -> Double {
    guard freq > 8000 else { return 0.0 }
    let norm = min(1.0, (log10(freq) - log10(8000)) / (log10(16000) - log10(8000)))
    return 2.0 * sin(norm * .pi / 2)
}
