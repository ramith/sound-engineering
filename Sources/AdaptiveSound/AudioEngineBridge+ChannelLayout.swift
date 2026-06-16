import AudioFormatKit
import AVFoundation
import Foundation

// MARK: - AudioEngineBridge channel-layout publish (Sprint 5b, M2-d)

/// The Swift side of the M2-d file-load -> kernel layout handshake, factored into a same-module
/// extension to keep the core class body focused (SwiftLint `function_body_length` /
/// `type_body_length`). Three responsibilities live here:
///
/// 1. `resolveSourceLayoutTag(channelLayout:channelCount:)` — pick the `AudioChannelLayoutTag` to
///    publish for a freshly opened source file (the file's own tag if it carries one; otherwise a
///    tag derived from the channel count so the kernel still gets correct BS.1770-5 weights).
/// 2. `publishChannelLayout(_:)` — the thin wrapper over the C-ABI `publishChannelLayoutTag`
///    (reachable through `DeviceBridge.h` -> `AudioUnitRegistrationBridge.h`), addressed at the
///    live effects AU via the same `dspAudioUnitHandle` accessor `publishEQGains` uses.
/// 3. `configureGraphForSource(channelCount:channelLayout:)` — the combined load-time step:
///    re-width the graph to the source's channel count, THEN publish the resolved layout tag.
///
/// All members are off-RT control-plane calls (no allocation/lock on the audio thread).
extension AudioEngineBridge {
    /// Resolve the `AudioChannelLayoutTag` to publish for a source with `channelCount` channels and
    /// an optional file-provided `channelLayout`.
    ///
    /// Priority:
    /// 1. The file's own `channelLayout.layoutTag`, if present and not the Unknown sentinel — the
    ///    most accurate descriptor.
    /// 2. Otherwise derive a tag from the channel count via `multichannelLayoutTag(for:)` (so 6 ->
    ///    MPEG_5_1_A, 8 -> MPEG_7_1_A — the tags the kernel's `ChannelLayoutDecoder` understands).
    /// 3. Otherwise (mono/stereo, or any count with no mapped multichannel tag) fall back to the
    ///    Stereo tag, which decodes to the neutral L/R weighting in the kernel.
    ///
    /// - Parameters:
    ///   - channelLayout: the source file's `processingFormat.channelLayout` (may be nil).
    ///   - channelCount: the source file's `processingFormat.channelCount` (N).
    /// - Returns: the layout tag to hand the kernel for the correct per-channel loudness weights.
    func resolveSourceLayoutTag(
        channelLayout: AVAudioChannelLayout?,
        channelCount: AVAudioChannelCount
    ) -> AudioChannelLayoutTag {
        if let tag = channelLayout?.layoutTag, tag != kAudioChannelLayoutTag_Unknown {
            return tag
        }
        if let derived = multichannelLayoutTag(for: channelCount) {
            return derived
        }
        return kAudioChannelLayoutTag_Stereo
    }

    /// Publish `tag` to the live effects AU's loudness kernel (off-RT control plane). No-op if the
    /// AU is not instantiated yet (`dspAudioUnitHandle` is nil), mirroring `publishEQGains`.
    func publishChannelLayout(_ tag: AudioChannelLayoutTag) {
        guard let handle = dspAudioUnitHandle else { return }
        publishChannelLayoutTag(handle, tag)
    }

    /// Load-time graph step (M2-d): re-width the graph to the source's channel count, THEN publish
    /// the source layout tag to the kernel. The order matters — `reconfigureGraph` is the
    /// same-count no-op for stereo, and publishing afterwards guarantees the kernel sees the tag
    /// for the width the graph just settled on.
    ///
    /// - Parameters:
    ///   - channelCount: the source file's channel count N.
    ///   - channelLayout: the source file's `processingFormat.channelLayout` (may be nil).
    func configureGraphForSource(
        channelCount: AVAudioChannelCount,
        channelLayout: AVAudioChannelLayout?
    ) {
        let tag = resolveSourceLayoutTag(channelLayout: channelLayout, channelCount: channelCount)

        // 1. Re-width the live graph to N (stereo -> same-count no-op; existing path untouched).
        reconfigureGraph(to: channelCount)

        // 2. Publish the layout so the kernel computes the correct BS.1770-5 per-channel weights.
        publishChannelLayout(tag)
    }
}
