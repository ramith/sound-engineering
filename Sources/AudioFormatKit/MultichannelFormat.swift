import AVFoundation
import Foundation

// MARK: - Multichannel format helper (Sprint 5b, M2-a)

/// Build the `AVAudioFormat` that drives a given channel count through the engine graph.
///
/// This is the single source of truth for the format the graph is connected at when the
/// pipeline goes multichannel (5.1 / 7.1). It is intentionally pure and side-effect free so
/// the offline `VerifyAUGraph` gate and unit tests can exercise it without an engine. It lives in
/// its own tiny library target (`AudioFormatKit`) so both the app (`AdaptiveSound`) and the
/// offline gate (`VerifyAUGraph`) link the exact same implementation — no drift between them.
///
/// Rules:
/// - `channels == 1` or `channels == 2`: returns `AVAudioFormat(standardFormatWithSampleRate:channels:)`.
///   For stereo this is byte-identical to the format the engine builds today in
///   `AudioEngineBridge.initialize()` (non-interleaved float32, standard layout), so the existing
///   stereo behaviour cannot regress.
/// - `channels >= 3`: standard formats only know mono/stereo, so a CoreAudio layout TAG is required.
///   The count is mapped to a tag (see `multichannelLayoutTag(for:)`), an `AVAudioChannelLayout` is
///   built from it, and the format is produced via
///   `AVAudioFormat(standardFormatWithSampleRate:channelLayout:)` (non-interleaved float32). The tags
///   chosen here (`MPEG_5_1_A` for 6, `MPEG_7_1_A` for 8) are exactly the ones the C++
///   `ChannelLayoutDecoder` handles, so the per-channel BS.1770 loudness weights stay consistent
///   between the engine format and the DSP kernel.
/// - Unsupported / unknown count (0, > 8, or any count with no mapped tag): returns `nil`. Callers are
///   expected to fall back to stereo.
///
/// - Parameters:
///   - channels: desired channel count (1...8 supported; others yield `nil`).
///   - sampleRate: the stream sample rate in Hz (the graph runs at 48 kHz today).
/// - Returns: a non-interleaved float32 `AVAudioFormat`, or `nil` if the count is unsupported.
public func multichannelFormat(for channels: AVAudioChannelCount, sampleRate: Double) -> AVAudioFormat? {
    // Mono / stereo: the standard-format path. For stereo this MUST match the engine's current
    // format exactly (AudioEngineBridge builds `standardFormatWithSampleRate: 48000, channels: 2`).
    if channels == 1 || channels == 2 {
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
    }

    // 3+ channels: a layout tag is mandatory — standardFormat alone cannot express > 2 channels.
    guard let layoutTag = multichannelLayoutTag(for: channels),
          let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag)
    else {
        return nil
    }

    return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: channelLayout)
}

/// Map a channel count to the CoreAudio layout tag the rest of the pipeline understands.
///
/// Only the counts the C++ `ChannelLayoutDecoder` handles are mapped:
/// - `6` → `kAudioChannelLayoutTag_MPEG_5_1_A`  (L R C LFE Ls Rs)
/// - `8` → `kAudioChannelLayoutTag_MPEG_7_1_A`  (L R C LFE Ls Rs Lc Rc)
///
/// Any other count returns `nil` (caller treats this as unsupported). Stereo and mono never reach
/// here — they take the standard-format path in `multichannelFormat(for:sampleRate:)`.
public func multichannelLayoutTag(for channels: AVAudioChannelCount) -> AudioChannelLayoutTag? {
    switch channels {
    case 6:
        return kAudioChannelLayoutTag_MPEG_5_1_A
    case 8:
        return kAudioChannelLayoutTag_MPEG_7_1_A
    default:
        return nil
    }
}
