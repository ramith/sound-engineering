// EQBuiltInPreset — the shipped presets and their 31 points (Sprint EQ, EQ0; moved here from
// the app's `Models/EQPreset.swift`, review F13). The single source of truth for every preset
// shape: the editor, the picker and the engine all read `points`.
//
// IDENTITY vs NAME: the raw value is the preset's stable id — persisted, so it never changes.
// It keeps the strings the app has always stored ("Flat", "Warm", …), so saved state decodes
// with no alias. What the user sees is `displayName`, which can change freely (e.g. the
// proposed "Loudness" → "Low Volume" rename touches the name only).

import Foundation

public enum EQBuiltInPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    // Analytic group (menu order F6).
    case flat = "Flat"
    case presence = "Presence"
    case clarity = "Clarity"
    case warm = "Warm"

    // House curves.

    /// Gentle bass + treble lift, inspired by the equal-loudness contours (Fletcher-Munson):
    /// compensates for reduced sensitivity at low and high frequencies at moderate levels.
    case loudness = "Loudness"

    /// Upper-midrange presence push centred around 3 kHz: brings vocal and acoustic-instrument
    /// detail forward without harshness above 8 kHz.
    case vocal = "Vocal"

    /// Near-flat reference with a subtle high-frequency air shelf (above 8 kHz), like the slight
    /// top-end lift of flat-response studio monitors in a treated room.
    case studio = "Studio"

    public var id: String {
        rawValue
    }

    /// The name shown to the user. Separate from the stable id (`rawValue`).
    public var displayName: String {
        switch self {
        case .flat: "Flat"
        case .presence: "Presence"
        case .clarity: "Clarity"
        case .warm: "Warm"
        case .loudness: "Loudness"
        case .vocal: "Vocal"
        case .studio: "Studio"
        }
    }

    /// The preset's 31 points (dB), one per band.
    public var points: [Float] {
        Self.pointsByPreset[self] ?? EQCurve.flat.points
    }

    /// Every preset's points, evaluated once at the nominal ISO centres.
    private static let pointsByPreset: [EQBuiltInPreset: [Float]] = Dictionary(
        uniqueKeysWithValues: allCases.map { preset in
            (preset, EQBands.nominalHz.map { Float(preset.gainDb(atHz: $0)) })
        }
    )

    /// The preset's shape: its gain (dB) at `hz`.
    private func gainDb(atHz hz: Double) -> Double {
        switch self {
        case .flat: 0
        case .presence: presenceGain(hz)
        case .clarity: clarityGain(hz)
        case .warm: warmGain(hz)
        case .loudness: loudnessGain(hz)
        case .vocal: vocalGain(hz)
        case .studio: studioGain(hz)
        }
    }
}

// MARK: - The preset shapes (the canonical formulas)

/// Presence: a bell over 1–4 kHz peaking at +8 dB at 2 kHz (0 at 4 kHz), then a smaller lobe
/// peaking at +4 dB at 4 kHz that decays to 0 by 8 kHz; 0 below 1 kHz.
private func presenceGain(_ hz: Double) -> Double {
    if hz >= 1000 && hz <= 4000 {
        8.0 * sin((log10(hz) - log10(1000)) / (log10(4000) - log10(1000)) * .pi)
    } else if hz > 4000 && hz <= 8000 {
        4.0 * sin((log10(8000) - log10(hz)) / (log10(8000) - log10(4000)) * .pi / 2)
    } else {
        0.0
    }
}

/// Clarity: a rising shelf from 1 kHz to +6 dB at 8 kHz, then a +4 dB lobe just above 8 kHz
/// that rolls off to 0 by 16 kHz; 0 below 1 kHz.
private func clarityGain(_ hz: Double) -> Double {
    if hz >= 1000 && hz <= 8000 {
        6.0 * sin((log10(hz) - log10(1000)) / (log10(8000) - log10(1000)) * .pi / 2)
    } else if hz > 8000 && hz <= 16000 {
        4.0 * sin((log10(16000) - log10(hz)) / (log10(16000) - log10(8000)) * .pi / 2)
    } else {
        0.0
    }
}

/// Warm: a low-mid lift from about +7 dB at 20 Hz to about +10 dB at 500 Hz, then decaying from
/// about +8 dB just above 500 Hz to about +3 dB at 2 kHz; 0 above 2 kHz.
private func warmGain(_ hz: Double) -> Double {
    if hz >= 20 && hz <= 500 {
        12.0 * (1.0 - exp(-log10(hz) / 1.5))
    } else if hz > 500 && hz <= 2000 {
        8.0 * exp(-(hz - 500) / 1500)
    } else {
        0.0
    }
}

/// Loudness: a bass half-cosine from +4 dB at 20 Hz to 0 at 500 Hz, plus a treble half-sine
/// from 0 at 3.15 kHz to +3 dB at 12.5 kHz and above.
private func loudnessGain(_ hz: Double) -> Double {
    var gain = 0.0
    if hz <= 500 {
        let position = (log10(hz) - log10(20)) / (log10(500) - log10(20))
        gain += 4.0 * cos(position * .pi / 2)
    }
    if hz >= 3150 {
        let position = min(1.0, (log10(hz) - log10(3150)) / (log10(12500) - log10(3150)))
        gain += 3.0 * sin(position * .pi / 2)
    }
    return gain
}

/// Vocal: a +6 dB bell centred at 3.15 kHz, rising from 0 at 500 Hz and falling to 0 at 8 kHz
/// along half-sines.
private func vocalGain(_ hz: Double) -> Double {
    if hz >= 500 && hz <= 3150 {
        6.0 * sin((log10(hz) - log10(500)) / (log10(3150) - log10(500)) * .pi / 2)
    } else if hz > 3150 && hz <= 8000 {
        6.0 * sin((log10(8000) - log10(hz)) / (log10(8000) - log10(3150)) * .pi / 2)
    } else {
        0.0
    }
}

/// Studio: 0 dB at and below 8 kHz, rising along a half-sine to +2 dB at 16 kHz and above.
private func studioGain(_ hz: Double) -> Double {
    guard hz > 8000 else { return 0.0 }
    let position = min(1.0, (log10(hz) - log10(8000)) / (log10(16000) - log10(8000)))
    return 2.0 * sin(position * .pi / 2)
}
