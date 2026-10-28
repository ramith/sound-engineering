import AudioDSP
import AudioFormatKit
@preconcurrency import AVFoundation
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

        // 1. Re-format the live graph to the source (stereo -> same-format no-op; existing path untouched).
        reconfigureGraph(channelCount: channelCount, layout: channelLayout)

        // 2. Publish the layout so the kernel computes the correct BS.1770-5 per-channel weights.
        publishChannelLayout(tag)

        // 3. The output state (M2) for the planner, and the layout's fold for the spatial unit.
        var state = outputState(roles: sourceRoles(channelCount: channelCount, layout: channelLayout))
        applyOutputState(state)
        _ = withSpatialAU { asSpatialPublishLayoutFold($0, &state) }
    }

    /// The output changed under the playing file (a re-establish after a device or route change): assemble the
    /// output state again — the transport the view model handed over, the device boundary — keeping the file's
    /// roles, and hand it to the planner, which re-plans the playing track protectively (F5) and sends the fold
    /// its new plan. Any bridge queue but `resampleQueue`; never under `stateLock`.
    func refreshOutputState() {
        let current = leveling.outputState
        let roles = withUnsafeBytes(of: current.sourceRoles) { Array($0.prefix(Int(current.sourceChannels))) }
        applyOutputState(outputState(roles: roles))
    }

    /// The one output state (M2) for the graph as it is configured now: the view model's transport hand-over,
    /// the graph's rate, its source width N with the file's `roles`, and the spatial unit's output width M.
    private func outputState(roles: [UInt8]) -> AsOutputState {
        var state = AsOutputState()
        state.transportType = levelingOutputTransport()
        let graph = playerNode?.outputFormat(forBus: 0)
        state.engineRateHz = (graph?.sampleRate ?? 0) > 0 ? graph?.sampleRate ?? 48000 : 48000
        state.sourceChannels = UInt32(graph?.channelCount ?? 2)
        state.outputChannels = UInt32(spatialNode?.outputFormat(forBus: 0).channelCount ?? graph?.channelCount ?? 2)
        let width = min(Int(state.sourceChannels), Int(AS_MAX_CHANNELS))
        withUnsafeMutableBytes(of: &state.sourceRoles) { slots in
            for slot in 0 ..< width {
                slots[slot] = slot < roles.count ? roles[slot] : UInt8(AsChannelRoleUnknown.rawValue)
            }
        }
        return state
    }

    /// The file's channel roles, from its labels: lane 1-B's one resolver (`asResolveChannelRoles`, through
    /// AudioFormatKit's `ChannelRoles`). It has not landed in this branch, so every role reads Unknown here:
    /// the fold then plays the table's Unknown row (0.5 to both sides) at its worst-case trim — never a
    /// truncation, never trim 0 — and the planner, seeing roles that differ from the analysis', keeps to the
    /// fallback trim. The combine replaces this body with the resolver's call (lane 2's report has the line).
    private func sourceRoles(channelCount: AVAudioChannelCount, layout _: AVAudioChannelLayout?) -> [UInt8] {
        [UInt8](repeating: UInt8(AsChannelRoleUnknown.rawValue), count: Int(min(channelCount, AVAudioChannelCount(AS_MAX_CHANNELS))))
    }
}
