import Foundation
import SettingsKit

// MARK: - OutputPathKind

/// Whether the active signal path is the AVFAudio-engine Enhanced path or the
/// bit-perfect Pure HAL path. Mutually exclusive at runtime.
enum OutputPathKind {
    case enhanced
    case pure
}

// MARK: - PureModeDecisionUI

/// User-facing mirror of the C-layer `PureModeDecision` enum.
/// `fullBitPerfect` — integer PCM delivered at the file's native rate.
/// `rateMatchedFloat` — float PCM, rate matched without SRC (no AVFAudio engine resampler).
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

// MARK: - DeviceVolume

/// The output device's own (hardware) volume, as Pure Mode reads it. Pure never scales the
/// bit-perfect stream, so this is the one gain on the Pure path — what Master Gain turns down while
/// Pure plays (`MasterGainOnPure`).
enum DeviceVolume: Equatable {
    /// The device has no volume the app can set (none on its main output, or not settable): its
    /// level is set on the device itself.
    case fixed
    /// The device's volume in dB on its own scale (0 dB = its full level), as the device reports it.
    case decibels(Float)
}

// MARK: - FoldState

/// The fold the spatial unit plays (R1.1-B, US-R1F-08; level-and-fold §S2): a file of 3 or more channels on a
/// narrower output, folded to stereo by the BS.775 matrix behind a backstop. What the "5.1 → stereo" badge and
/// the backstop's meter read. It describes the graph as configured for the current file — playing or paused.
struct FoldState: Equatable {
    /// N: the file's channels.
    var sourceChannels: Int
    /// M: the output's (2: the fold is stereo).
    var outputChannels: Int
    /// The fold is the playing track's plan; false: the layout's fold at its worst-case trim (no plan yet).
    var fromPlan: Bool
    /// The fold's trim, dB (≤ 0).
    var trimDb: Float
    /// The LFE's per-side gain in the fold (0: omitted).
    var lfeGain: Float
    /// The deepest gain reduction the backstop applied since this fold began, dB (≥ 0; the trim keeps it 0).
    var backstopPeakGrDb: Float

    /// Whether the fold plays the LFE.
    var lfeIncluded: Bool {
        lfeGain > 0
    }
}

// MARK: - SignalPathInfo

/// Snapshot of the active signal path, updated at 20 Hz from `engine.snapshot()`.
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

    /// The playing track's own bit depth, as Pure's decoder read it (0: compressed or unknown) — what
    /// `bitDepth` is held against for "not bit-perfect" (C-33). 0 on Enhanced.
    var sourceBitDepth: UInt32 = 0

    /// `true` when the device AU output format is float (vs integer PCM).
    var isFloat: Bool = false

    /// Active decoder backend. `nil` when the Enhanced path is in use.
    var decoder: DecoderKindUI?

    /// Why Pure isn't playing bit-perfect, or isn't playing (council C-34): set when Pure was asked
    /// for and declined or waits (Enhanced plays), or plays but not bit-perfect. `nil` when Pure isn't
    /// asked for, or plays bit-perfect.
    var pureReason: PureModeReason?

    /// `true` when Pure was asked for but Enhanced plays — it declined, or it waits (`pureReason`).
    var fellBackToEnhanced: Bool {
        pureReason.map { !$0.purePlays } ?? false
    }

    /// `true` when playback was paused because the active output device disappeared (e.g. a
    /// Bluetooth device disconnected). The view model surfaces this and clears `isPlaying`; the
    /// flag is cleared on the next `startAudio`.
    var interrupted: Bool = false

    /// The output device's own volume while Pure plays — read when Pure starts (in the same snapshot
    /// that turns the path Pure) and kept current by a listener on the device. `.fixed` holds the
    /// Master Gain slider at 0 dB (the device has no volume to turn down). `nil` on Enhanced.
    var deviceVolume: DeviceVolume?

    /// The fold the spatial unit plays (S2): `nil` when nothing folds, and always on Pure. `snapshot()` reads
    /// it from the unit's atomics; it is never stored.
    var fold: FoldState?

    /// The song playing's leveling plan as the engine made it (R1.1-B, lane 3-B): the Settings row's "This song"
    /// line and the fold badge's "· measuring". `nil` on Pure and before any plan. `snapshot()` reads it; it is
    /// never stored.
    var leveling: LevelingReadout?

    // MARK: - Enhancement overlay (F4 — copied from the VM: `refreshSignalPathIntents`, the tick)

    /// Current Reimagine intensity in [0, 1], copied from `AudioViewModel.intensity` each tick.
    /// Used by the signal-path badge to display "… · 23%". Default 0.
    var intensityLinear: Float = 0

    /// The crossfeed strength while crossfeed plays (chosen, on headphones), copied from the view
    /// model each tick; `nil` when it doesn't.
    var crossfeedStrength: CrossfeedStrength?

    /// Whether the crossfeed played on the effects unit's last block (S2, KI-SND-06): the engine's own bypass,
    /// so `false` on a folded surround file — crossfeed is stereo-only and runs before the fold — and on the
    /// bit-perfect path. `nil` when the engine doesn't say (no live effects unit; the test and sheet engines).
    /// `snapshot()` reads it from the kernel's atomic; it is never stored.
    var crossfeedEngaged: Bool?

    /// The crossfeed the listener hears — the hero's "XF" chip: its strength while it plays, on the
    /// Enhanced path, whatever Intensity is (crossfeed is an output stage of its own, founder
    /// decision 2026-10-14); `nil` on Pure, which bypasses the DSP, and whenever the engine says it does
    /// not play (a folded surround file, KI-SND-06).
    var audibleCrossfeed: CrossfeedStrength? {
        path == .enhanced && crossfeedEngaged != false ? crossfeedStrength : nil
    }

    // MARK: - The path that last played (R1.1-B fix round: the DSP rows, paused)

    /// The path the last song played on, which the DSP rows follow (`AudioViewModel.dspRowAvailability`): the path
    /// in use while a song plays, and — while nothing does (paused, stopped, the output lost, a start on its way) —
    /// the one that last played, so a pause or a stop never changes the rows (founder's decisions, 2026-10-30). `nil`
    /// until a song has played since launch. The view model carries it from snapshot to snapshot
    /// (`carryPlayedPath`); the engine never sets it.
    var playedPath: OutputPathKind?

    /// Carry `playedPath` on from `previous`, the snapshot this one replaces: the path in use when a song `plays`
    /// (playing, nothing on its way) and the output isn't lost; else what `previous` last saw play.
    mutating func carryPlayedPath(from previous: SignalPathInfo, plays: Bool) {
        playedPath = plays && !interrupted ? path : previous.playedPath
    }
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

    /// `rateString` as VoiceOver speaks it — "48 kilohertz", "44.1 kilohertz": read aloud, "kHz" is
    /// three letters. Every spoken rate goes through here (the device pill, the footer, the hero, the
    /// Settings rows).
    static func spokenRateString(_ rate: Double) -> String {
        rateString(rate).replacing(" kHz", with: " kilohertz")
    }

    /// Formats bit depth into a compact string in plain words: "24-bit" for integer PCM (the usual
    /// case, so it goes unsaid) and "32-bit float" when the samples are floating point.
    /// Returns `nil` when neither `bitDepth` nor `isFloat` carries information (Enhanced path idle).
    static func bitsString(bitDepth: UInt32, isFloat: Bool) -> String? {
        if bitDepth > 0 {
            return isFloat ? "\(bitDepth)-bit float" : "\(bitDepth)-bit"
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

    /// Sample rate as VoiceOver speaks it, using `achievedSampleRate`.
    var spokenRate: String {
        SignalPathInfo.spokenRateString(achievedSampleRate)
    }

    /// Bit-depth + kind formatted for display, using `bitDepth` and `isFloat`.
    var formattedBits: String? {
        SignalPathInfo.bitsString(bitDepth: bitDepth, isFloat: isFloat)
    }
}
