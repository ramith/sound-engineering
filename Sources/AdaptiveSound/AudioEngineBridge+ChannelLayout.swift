import AudioDSP
import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation
import TrackLoudnessKit

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
///    live effects AU via the same `withEffectsAU` borrow `publishEQ` uses.
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
    /// AU is not instantiated yet, mirroring `publishEQ`.
    func publishChannelLayout(_ tag: AudioChannelLayoutTag) {
        _ = withEffectsAU { publishChannelLayoutTag($0, tag) }
    }

    /// Load-time graph step (M2-d, F1, M2): re-format the graph to the source — its own channels in its own
    /// order (`engineFormat`, the one F1 function) — THEN publish the source layout tag to the kernel, THEN
    /// assemble the one output state the planner plans against and give the spatial unit the layout's fold.
    /// The order matters: `reconfigureGraph` is the same-format no-op for stereo, and everything after it reads
    /// the format the graph just settled on. On `engineQueue`, before the file becomes audible, so the fold is
    /// in place (the layout's, at its worst-case trim) before the plan refines it.
    ///
    /// - Parameters:
    ///   - channelCount: the source file's channel count N.
    ///   - channelLayout: the source file's `processingFormat.channelLayout` (may be nil).
    func configureGraphForSource(
        channelCount: AVAudioChannelCount,
        channelLayout: AVAudioChannelLayout?
    ) {
        let tag = resolveSourceLayoutTag(channelLayout: channelLayout, channelCount: channelCount)
        // The device's own width, read before the reconfigure as the reconfigure reads it: offline, re-enabling
        // manual rendering at a narrower boundary would make that boundary the stand-in device.
        let deviceChannels = outputDeviceChannels()

        // 1. Re-format the live graph to the source (stereo -> same-format no-op; existing path untouched).
        reconfigureGraph(channelCount: channelCount, layout: channelLayout)

        // 2. Publish the layout so the kernel computes the correct BS.1770-5 per-channel weights.
        publishChannelLayout(tag)

        // 3. The output state (M2) for the planner — the transport stays the view model's — and the layout's fold
        //    for the spatial unit, against the state the planner now holds.
        var state = applyOutputState(outputState(roles: sourceRoles(channelCount: channelCount, layout: channelLayout),
                                                 deviceChannels: deviceChannels))
        _ = withSpatialAU { asSpatialPublishLayoutFold($0, &state) }
    }

    /// The output changed under the playing file (a re-establish after a device or route change): read the device
    /// boundary again — the graph's rate and the width M the listener's output plays it on — and hand it to the
    /// planner with the graph's source width, which re-plans the playing track protectively (F5) and sends the fold
    /// its new plan. The roles and the transport keep their owners' (the configure's, the view model's); a graph
    /// being re-widened for another file is left to its configure (review S1). Any bridge queue but
    /// `resampleQueue`; never under `stateLock`.
    func refreshOutputState() {
        applyDeviceBoundary(graphOutputState(deviceChannels: outputDeviceChannels()))
    }

    /// The output state (M2) of the graph as it is configured now, without the file's roles: its rate, its source
    /// width N, and the width M the listener's output plays it on (`heardOutputChannels`) — `deviceChannels` the
    /// device's own width. The transport is not the graph's to say (the planner keeps the view model's).
    private func graphOutputState(deviceChannels: AVAudioChannelCount) -> AsOutputState {
        let graph = playerNode?.outputFormat(forBus: 0)
        let source = graph?.channelCount ?? 2
        let boundary = spatialNode?.outputFormat(forBus: 0).channelCount ?? source
        var state = AsOutputState()
        state.engineRateHz = (graph?.sampleRate ?? 0) > 0 ? graph?.sampleRate ?? 48000 : 48000
        state.sourceChannels = UInt32(source)
        state.outputChannels = UInt32(Self.heardOutputChannels(source: source, boundary: boundary,
                                                               device: deviceChannels))
        return state
    }

    /// The output state (M2) of the graph as it is configured now (`graphOutputState`), the file's `roles` in it.
    private func outputState(roles: [UInt8], deviceChannels: AVAudioChannelCount) -> AsOutputState {
        var state = graphOutputState(deviceChannels: deviceChannels)
        let width = min(Int(state.sourceChannels), Int(AS_MAX_CHANNELS))
        withUnsafeMutableBytes(of: &state.sourceRoles) { slots in
            for slot in 0 ..< width {
                slots[slot] = slot < roles.count ? roles[slot] : UInt8(AsChannelRoleUnknown.rawValue)
            }
        }
        return state
    }

    /// M, the width the listener's output plays a source of `source` channels on, the spatial unit's output being
    /// `boundary` channels wide on a device of `device` (0: not negotiated). The spatial unit shapes a multichannel
    /// source: every channel, or the stereo fold (C1) — so M is its output. A mono or stereo source crosses the
    /// boundary as it is and the system lays it out on the device: a mono file plays on both sides of a stereo device
    /// at 0 dB (F8, the founder's XM4 listen, 2026-10-26), heard as dual mono — so M is the device's width. The
    /// planner's mono rule (+3.01 LU when one channel plays on two or more) reads it.
    static func heardOutputChannels(source: AVAudioChannelCount, boundary: AVAudioChannelCount,
                                    device: AVAudioChannelCount) -> AVAudioChannelCount {
        source > 2 ? boundary : max(boundary, device)
    }

    /// The output device's own width as the engine reports it (its output node's), 0 before it is known.
    private func outputDeviceChannels() -> AVAudioChannelCount {
        avEngine?.outputNode.outputFormat(forBus: 0).channelCount ?? 0
    }

    /// The file's channel roles, from its labels: the one resolver (TrackLoudnessKit's `ChannelRoles`, over
    /// AudioDSP's `asResolveChannelRoles`) — the same roles the analysis measured with, so the planner's fold and
    /// this unit's agree. Min(N, 8) values; Unknown × 8 for a wider file; none for 0.
    private func sourceRoles(channelCount: AVAudioChannelCount, layout: AVAudioChannelLayout?) -> [UInt8] {
        ChannelRoles.resolve(channelCount: channelCount, layout: layout)
    }
}
