import Foundation

// MARK: - OutputPathKind

/// Whether the active signal path is the AVAudioEngine-based Enhanced path or the
/// bit-perfect Pure HAL path. Mutually exclusive at runtime.
enum OutputPathKind {
    case enhanced
    case pure
}

// MARK: - PureModeDecisionUI

/// User-facing mirror of the C-layer `PureModeDecision` enum.
/// `fullBitPerfect` — integer PCM delivered at the file's native rate.
/// `rateMatchedFloat` — float PCM, rate matched without SRC (no AVAudioEngine resampler).
/// `fallbackEnhanced` — Pure was requested but the device or file forced an Enhanced fallback.
enum PureModeDecisionUI {
    case fullBitPerfect
    case rateMatchedFloat
    case fallbackEnhanced
}

// MARK: - DecoderKindUI

/// Which decoder backend is active in the Pure path.
/// `nil` on `SignalPathInfo` when the Enhanced path is active.
enum DecoderKindUI {
    case apple
    case ffmpeg
}

// MARK: - SignalPathInfo

/// Snapshot of the active signal path, updated at 20 Hz from `engine.currentSignalPath()`.
/// Equatable so `@Observable` change tracking suppresses redundant UI renders when state is stable.
struct SignalPathInfo: Equatable {
    /// Whether the Enhanced or Pure HAL path is rendering.
    var path: OutputPathKind = .enhanced

    /// The Pure-Mode policy decision that was applied (or `fallbackEnhanced` when Enhanced).
    var decision: PureModeDecisionUI = .fallbackEnhanced

    /// Sample rate the device is actually running at (Hz). 0 when not yet started.
    var achievedSampleRate: Double = 0

    /// Bit depth negotiated at the device boundary. 0 when the path is float or not started.
    var bitDepth: UInt32 = 0

    /// `true` when the device AU output format is float (vs integer PCM).
    var isFloat: Bool = false

    /// Active decoder backend. `nil` when the Enhanced path is in use.
    var decoder: DecoderKindUI?

    /// `true` when Pure mode was requested by the user but capability evaluation or engine
    /// startup forced a fallback to Enhanced. Cleared when Pure mode is not requested.
    var fellBackToEnhanced: Bool = false

    /// `true` when playback was paused because the active output device disappeared (e.g. a
    /// Bluetooth device disconnected). The view model surfaces this and clears `isPlaying`; the
    /// flag is cleared on the next `startAudio`.
    var interrupted: Bool = false

    // MARK: - Enhancement overlay (F4 — copied from VM in tickSpectrum)

    /// Current Reimagine intensity in [0, 1], copied from `AudioViewModel.intensity` each tick.
    /// Used by the signal-path badge to display "… · 23%". Default 0.
    var intensityLinear: Float = 0

    /// Active crossfeed strength, or `nil` when crossfeed is off.
    /// Gated on `intensityLinear > 0` before being shown in the badge (§9 nice-to-have:
    /// don't display an inaudible-chain badge at 0 % intensity).
    var crossfeedStrength: CrossfeedStrength?
}

// MARK: - Display helpers

extension SignalPathInfo {
    /// Formats a sample rate in Hz as a kHz string, e.g. 48 000 → "48 kHz", 44 100 → "44.1 kHz".
    /// Returns "-- kHz" when `rate` is zero (not yet started).
    static func rateString(_ rate: Double) -> String {
        guard rate > 0 else { return "-- kHz" }
        // Integer division avoids floating-point noise: 48 000 % 1 000 == 0 → "48 kHz".
        let rateHz = Int(rate.rounded())
        if rateHz % 1000 == 0 {
            return "\(rateHz / 1000) kHz"
        }
        return String(format: "%.1f kHz", Double(rateHz) / 1000.0)
    }

    /// Formats bit depth + float/int kind into a compact string, e.g. "32-bit float", "24-bit int".
    /// Returns `nil` when neither `bitDepth` nor `isFloat` carries information (Enhanced path idle).
    static func bitsString(bitDepth: UInt32, isFloat: Bool) -> String? {
        if bitDepth > 0 {
            let kind = isFloat ? "float" : "int"
            return "\(bitDepth)-bit \(kind)"
        }
        if isFloat {
            return "float"
        }
        return nil
    }

    // MARK: Convenience instance shortcuts

    /// Sample rate formatted for display, using `achievedSampleRate`.
    var formattedRate: String {
        SignalPathInfo.rateString(achievedSampleRate)
    }

    /// Bit-depth + kind formatted for display, using `bitDepth` and `isFloat`.
    var formattedBits: String? {
        SignalPathInfo.bitsString(bitDepth: bitDepth, isFloat: isFloat)
    }
}
