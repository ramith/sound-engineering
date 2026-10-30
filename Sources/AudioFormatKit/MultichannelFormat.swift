import AVFoundation
import Foundation

// MARK: - The format a source plays and is analysed in (R1.1-B, F1)

/// The widest source the engine graph carries: the DSP kernel's `kMaxChannels` (AudioDSP's
/// `AudioConstants.h`, C++ and so not visible here). A wider file plays through today's stereo fallback.
let engineMaxChannels: AVAudioChannelCount = 8

/// The format a source plays in on the Enhanced path, and is analysed in, at the engine's rate: **its own
/// channels in its own order** (level-and-fold design, F1). This is the one function the graph's source width
/// (`AudioEngineBridge.configureGraphForSource`) and the analysis pass's converter both call, so what is
/// measured is what plays.
///
/// - 1 or 2 channels: today's formats, `AVAudioFormat(standardFormatWithSampleRate:channels:)` (§8½ C1).
/// - 3 … `engineMaxChannels`: the source's own channel layout at `sampleRate` — its tag, its bitmap or its
///   per-channel labels, whatever the decoder reported — or `DiscreteInOrder | N` when it reports none. A
///   converter from the source to this format changes the RATE only: every channel keeps its slot and its
///   label, so the roles read from the file's labels (the one role resolver) name the right slots. Before F1
///   the graph took a layout derived from the channel COUNT (6 → MPEG 5.1 A, 8 → MPEG 7.1 A, anything else →
///   stereo), and Apple's converter re-laid the file into it by label: an AAC / ALAC 5.1 file was reordered,
///   a WAVE 7.1 file lost its back pair, and 3-, 4-, 5- and 7-channel files kept only L and R.
/// - 0 or more than `engineMaxChannels`: `nil` (the caller keeps today's stereo fallback).
///
/// - Parameters:
///   - source: the source's processing format (`AVAudioFile.processingFormat`); only its channel count and
///     layout are read.
///   - sampleRate: the engine's rate (48 kHz).
public func engineFormat(forSource source: AVAudioFormat, sampleRate: Double) -> AVAudioFormat? {
    engineFormat(channelCount: source.channelCount, layout: source.channelLayout, sampleRate: sampleRate)
}

/// `engineFormat(forSource:sampleRate:)` from a source's channel count and layout (`nil`: none reported).
public func engineFormat(channelCount: AVAudioChannelCount, layout: AVAudioChannelLayout?,
                         sampleRate: Double) -> AVAudioFormat? {
    guard channelCount > 2 else {
        return channelCount == 0 ? nil : AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)
    }
    guard channelCount <= engineMaxChannels else { return nil }
    let own = layout.flatMap { $0.channelCount == channelCount ? $0 : nil }
        ?? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channelCount)
    return own.map { AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: $0) }
}

// MARK: - Formats by channel count (Sprint 5b, M2-a)

/// A graph format for a channel COUNT, with no source behind it: the offline `VerifyAUGraph` gate's synthetic
/// widths, the stereo fallback and the folded device boundary. A source's own format is
/// `engineFormat(forSource:sampleRate:)` (F1) — never this, which would re-lay its channels.
///
/// - `channels == 1` or `channels == 2`: `AVAudioFormat(standardFormatWithSampleRate:channels:)` — for stereo
///   byte-identical to the format `AudioEngineBridge.initialize()` builds (non-interleaved float32).
/// - `6` / `8`: the layout tag `multichannelLayoutTag(for:)` names (non-interleaved float32).
/// - Any other count: `nil`.
///
/// - Parameters:
///   - channels: the channel count (1, 2, 6 or 8).
///   - sampleRate: the stream sample rate in Hz (the graph runs at 48 kHz).
/// - Returns: a non-interleaved float32 `AVAudioFormat`, or `nil` if the count has no mapping.
public func multichannelFormat(for channels: AVAudioChannelCount, sampleRate: Double) -> AVAudioFormat? {
    if channels == 1 || channels == 2 {
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
    }
    guard let layoutTag = multichannelLayoutTag(for: channels),
          let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag)
    else {
        return nil
    }
    return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: channelLayout)
}

/// The CoreAudio layout tag a bare channel count stands for, where the C++ `ChannelLayoutDecoder` knows one:
/// - `6` → `kAudioChannelLayoutTag_MPEG_5_1_A`  (L R C LFE Ls Rs)
/// - `8` → `kAudioChannelLayoutTag_MPEG_7_1_A`  (L R C LFE Ls Rs Lc Rc)
///
/// Any other count returns `nil`. Used for synthetic formats (`multichannelFormat(for:sampleRate:)`) and as
/// the kernel's layout-tag fallback for a file that reports none.
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

// MARK: - Device-width resolution (Sprint 5b M2-d / M3)

/// Resolve the device-boundary render format: the width M the spatial unit renders the source's N channels
/// to. The single source of truth for the device-width choice, so the production graph AND the offline
/// `VerifyAUGraph` gate call ONE implementation rather than hand-copied mirrors that can drift (review
/// finding TOOL-1). The bridge passes `engine.outputNode`'s channel count as `deviceChannels`; the gate passes
/// its simulated device width.
///
/// - The device takes every channel (`deviceChannels >= N`), or has not negotiated yet (0): M = N, the source
///   format itself (`sourceFormat` — the file's own layout, F1).
/// - A multichannel source (N > 2) on a narrower device: **stereo** — the spatial unit folds N to 2 (ITU-R
///   BS.775), and never keeps the first M channels, whatever the device's width (§8½ C1: 7.1 on a 5.1
///   output folds to stereo; a 7.1 → 5.1 fold waits for the Engine sprint).
/// - Mono or stereo on a narrower device: M = `deviceChannels` (today's behaviour).
///
/// - Parameters:
///   - sourceFormat: the source (processing) format at width N.
///   - deviceChannels: the negotiated output-device channel count.
/// - Returns: the device-boundary format; never wider than the source.
public func deviceWidthFormat(sourceFormat: AVAudioFormat,
                              deviceChannels: AVAudioChannelCount) -> AVAudioFormat {
    let sourceChannels = sourceFormat.channelCount
    guard deviceChannels > 0, deviceChannels < sourceChannels else { return sourceFormat }
    let deviceWidth = sourceChannels > 2 ? 2 : deviceChannels
    return multichannelFormat(for: deviceWidth, sampleRate: sourceFormat.sampleRate) ?? sourceFormat
}
