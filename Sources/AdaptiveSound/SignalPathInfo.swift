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

    /// `true` when this process holds hog mode (exclusive access) on the output device.
    var exclusiveHog: Bool = false

    /// `true` when the device nominal rate was changed to match the file's sample rate.
    var rateMatched: Bool = false

    /// Active decoder backend. `nil` when the Enhanced path is in use.
    var decoder: DecoderKindUI?

    /// `true` when Pure mode was requested by the user but capability evaluation or engine
    /// startup forced a fallback to Enhanced. Cleared when Pure mode is not requested.
    var fellBackToEnhanced: Bool = false
}
