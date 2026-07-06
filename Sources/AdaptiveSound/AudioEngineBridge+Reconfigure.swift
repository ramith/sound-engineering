import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge multichannel reconfigure lifecycle (Sprint 5b, M2-c)

/// The live-graph re-width lifecycle, factored out of `AudioEngineBridge.swift` into a same-module
/// extension to keep the core class body focused (SwiftLint `type_body_length`). The public entry
/// point is `reconfigureGraph(to:)`; the helpers below are `private` so they stay scoped to this
/// file. The members it touches (`avEngine`, `playerNode`, `dspAudioUnit`, `spatialAudioUnit`, the
/// analyzer arrays, the tap install/remove) are module-internal on the base class so
/// this extension — in a separate file — can reach them.
/// The four live-graph node references threaded through the reconfigure lifecycle's private
/// helpers (`reconnectGraph`, `applyReconfigure`). Grouping them keeps those functions under the
/// SwiftLint parameter-count ceiling without losing the descriptive per-node names at call sites.
private struct ReconfigureGraphNodes {
    let engine: AVAudioEngine
    let player: AVAudioPlayerNode
    let effects: AVAudioUnit
    let spatial: AVAudioUnit
}

extension AudioEngineBridge {
    // MARK: - Multichannel reconfigure lifecycle (Sprint 5b, M2-c / M3-3)

    /// Reconfigure the live graph to carry `channels` channels end-to-end.
    ///
    /// This is the spike-validated lifecycle that re-widths a SINGLE running engine without a crash
    /// or a silent downmix. It must run OFF the audio thread (it stops the player, removes taps,
    /// reconnects nodes, resizes the per-channel analyzers, and re-starts the engine). It is a no-op
    /// when `channels` already matches the current graph width, so the stereo path is byte-for-byte
    /// unchanged until a real reconfigure is requested.
    ///
    /// Both custom AU nodes are re-widthed together (Sprint 5b M3-3): the chain
    /// `player -> effectsAU -> spatialAU -> mainMixer -> output` is reconnected with the effects-AU
    /// edges at the source/processing width N and the spatial-AU output + mixer + output at the
    /// device width M = min(N, deviceChannels) (M2-d).
    ///
    /// The hard-won findings from the spike are baked in here:
    /// - The `mainMixerNode -> outputNode` reconnect (`reconnectGraph`) is MANDATORY: without it the
    ///   mixer silently downmixes to its own output width and only L/R carry signal for > 2ch.
    /// - Analyzer arrays are resized only while the taps are removed — never on the audio thread.
    /// - Production uses `engine.pause()` (device width is fixed; pause keeps attachments and is
    ///   lighter than stop). The offline harness can only change WIDTH via stop -> re-enable manual
    ///   rendering -> start, so `reconfigureGraph` detects manual-rendering mode and branches.
    ///
    /// - Parameter channels: the desired graph width (1...8; counts with no `multichannelFormat`
    ///   mapping fall back to stereo, and stereo failing aborts gracefully without a crash).
    func reconfigureGraph(to channels: AVAudioChannelCount) {
        // 1. Same-count guard — keep the existing path 100% untouched until a real reconfigure.
        guard channels != currentGraphWidth else { return }
        guard let engine = avEngine, let player = playerNode,
              let effects = dspAudioUnit, let spatial = spatialAudioUnit else { return }

        // 2. Quiesce the audio thread: stop any streaming-resampler loop (bump generation + drop
        //    session so no in-flight buffer schedules onto the graph we're about to reconnect), then
        //    stop the player and remove every tap before touching nodes.
        stopEnhancedResampler()
        player.stop()
        removeSpectrumTap()

        let graphSampleRate = currentGraphSampleRate

        // 5. Resolve the target format, falling back to stereo, then aborting gracefully.
        guard let format = resolveReconfigureFormat(for: channels, sampleRate: graphSampleRate) else {
            // multichannelFormat returned nil even for the stereo fallback — cannot proceed safely.
            abortReconfigure(reason: "no usable format for \(channels)ch (stereo fallback also nil)")
            return
        }
        let resolvedChannels = format.channelCount

        // 4 + 6 + 8: pause (or offline stop), reconnect at the new width, then restart the engine.
        // 7. Resize analyzers while taps are removed (off the audio thread) — done inside the helper.
        // 9 + 10: reinstall taps + publish the new running state — done inside the helper.
        do {
            let nodes = ReconfigureGraphNodes(engine: engine, player: player, effects: effects, spatial: spatial)
            try applyReconfigure(nodes: nodes, format: format, channels: resolvedChannels)
        } catch {
            // 8. engine.start() threw (an AU could not re-allocate render resources at this width):
            // transition to a safe state and log — never crash the app.
            abortReconfigure(reason: "engine.start() failed at \(resolvedChannels)ch: \(error)")
        }
    }

    /// The graph's current channel width, derived from the player node's negotiated output format.
    /// Falls back to the analyzer-array count (kept in lock-step) and finally to 2 (the init width).
    private var currentGraphWidth: AVAudioChannelCount {
        if let player = playerNode {
            let width = player.outputFormat(forBus: 0).channelCount
            if width > 0 { return width }
        }
        if !afterAnalyzers.isEmpty { return AVAudioChannelCount(afterAnalyzers.count) }
        return 2
    }

    /// The sample rate the graph runs at (48 kHz today). Read from the live player output format so
    /// the reconfigured format keeps the rate stable across a width change.
    private var currentGraphSampleRate: Double {
        let rate = playerNode?.outputFormat(forBus: 0).sampleRate ?? 0
        return rate > 0 ? rate : 48000.0
    }

    /// Resolve the format for `channels`, falling back to stereo if the requested count is unmapped.
    /// Returns `nil` only if even the stereo fallback cannot be built (should never happen).
    private func resolveReconfigureFormat(
        for channels: AVAudioChannelCount,
        sampleRate: Double
    ) -> AVAudioFormat? {
        if let format = multichannelFormat(for: channels, sampleRate: sampleRate) {
            return format
        }
        // Requested count has no layout tag (e.g. 3/4/5/7) — fall back to stereo rather than abort.
        return multichannelFormat(for: 2, sampleRate: sampleRate)
    }

    /// Reconnect every edge of the two-AU graph at the new width:
    /// `player -> effectsAU -> spatialAU -> mainMixer -> output`.
    ///
    /// - `player -> effectsAU -> spatialAU` connect at the SOURCE/processing width N (`sourceFormat`).
    /// - `spatialAU -> mainMixer -> output` connect at the DEVICE width M (`deviceFormat`).
    ///
    /// The spatial AU derives its in/out channel counts from these negotiated bus formats. The
    /// `mainMixerNode -> outputNode` line is the spike's critical finding: without it the mixer
    /// silently downmixes to its own output width.
    private func reconnectGraph(
        nodes: ReconfigureGraphNodes,
        sourceFormat: AVAudioFormat,
        deviceFormat: AVAudioFormat
    ) {
        let engine = nodes.engine
        engine.connect(nodes.player, to: nodes.effects, format: sourceFormat)
        engine.connect(nodes.effects, to: nodes.spatial, format: sourceFormat)
        engine.connect(nodes.spatial, to: engine.mainMixerNode, format: deviceFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: deviceFormat)
    }

    /// Resize the per-channel before/after analyzer arrays to `channels`, off the audio thread.
    /// Only ever called while the taps are removed (so no tap block can index a stale array).
    private func resizeAnalyzers(to channels: AVAudioChannelCount, sampleRate: Double) {
        let count = Int(channels)
        beforeAnalyzers = (0 ..< count).map { _ in
            SpectrumAnalyzer(fftSize: SpectrumConstants.fftSize, sampleRate: Float(sampleRate))
        }
        afterAnalyzers = (0 ..< count).map { _ in
            SpectrumAnalyzer(fftSize: SpectrumConstants.fftSize, sampleRate: Float(sampleRate))
        }
    }

    /// Pause (or, offline, stop) the engine, reconnect the two-AU chain at `format`, resize
    /// analyzers, restart, then reinstall taps and publish `.running`. Throws if `engine.start()`
    /// fails so the caller can land in a safe state.
    ///
    /// The device width M is resolved by `deviceWidthFormat` (M2-d): M = min(N, deviceChannels)
    /// where deviceChannels is the engine output node's negotiated width. So a 5.1 source (N=6) on a
    /// stereo device reconnects the effects edges at N=6 and the spatial output + mixer + output at
    /// M=2 — the spatial AU renders 6->2 via its S4 `device<N` stub (no naive mixer downmix). For
    /// M == N the spatial AU is a bit-exact identity route. The real binaural fold is S4, on the
    /// spatial AU side — see the `TODO(S4)` marker in `connectInitialGraph`.
    private func applyReconfigure(
        nodes: ReconfigureGraphNodes,
        format: AVAudioFormat,
        channels: AVAudioChannelCount
    ) throws {
        let engine = nodes.engine
        // Device width M = min(N, deviceChannels). Resolved BEFORE any stop/re-enable so the output
        // node still reports the in-effect device width (the manual-rendering width when offline).
        let deviceFormat = deviceWidthFormat(engine: engine, sourceFormat: format)
        if engine.isInManualRenderingMode {
            // Offline: the manual-rendering format is immutable while running, so changing WIDTH
            // requires stop -> re-enable manual rendering at the new (device-width) format -> start.
            engine.stop()
            reconnectGraph(nodes: nodes, sourceFormat: format, deviceFormat: deviceFormat)
            resizeAnalyzers(to: channels, sampleRate: format.sampleRate)
            try engine.enableManualRenderingMode(.offline, format: deviceFormat,
                                                 maximumFrameCount: manualRenderingBlockSize)
            try engine.start()
        } else {
            // Live device: pause keeps attachments and is lighter than stop. The device width is
            // fixed, so reconnecting at the resolved formats + restart re-allocates both AUs.
            engine.pause()
            reconnectGraph(nodes: nodes, sourceFormat: format, deviceFormat: deviceFormat)
            resizeAnalyzers(to: channels, sampleRate: format.sampleRate)
            try engine.start()
        }

        // 9. Reinstall taps using each node's freshly negotiated outputFormat(forBus: 0). The
        // "after" tap stays on the EFFECTS AU output (the N-channel processed signal). The source
        // layout tag is published separately by `configureGraphForSource` (M2-d) AFTER this returns,
        // so the kernel sees the tag for the width the graph just settled on.
        installSpectrumTap()
    }

    /// Land in a safe state after a reconfigure failure: pause the engine if it is still running
    /// and log. Never crashes — a failed reconfigure must degrade, not abort.
    private func abortReconfigure(reason: String) {
        print("reconfigureGraph: aborting — \(reason)")
        if let engine = avEngine, engine.isRunning, !engine.isInManualRenderingMode {
            engine.pause()
        }
    }

    /// Maximum render block the offline manual-rendering path re-enables with. Mirrors the
    /// `VerifyAUGraph` gate's block size so the offline reconfigure path is exercised identically.
    private var manualRenderingBlockSize: AVAudioFrameCount {
        512
    }
}
