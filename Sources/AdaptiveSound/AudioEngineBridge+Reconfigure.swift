import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge multichannel reconfigure lifecycle (Sprint 5b, M2-c)

/// The live-graph re-width lifecycle, factored out of `AudioEngineBridge.swift` into a same-module
/// extension to keep the core class body focused (SwiftLint `type_body_length`). The public entry
/// point is `reconfigureGraph(to:)`; the helpers below are `private` so they stay scoped to this
/// file. The members it touches (`avEngine`, `playerNode`, `effectsNode`, `spatialAudioUnit`, the
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

    /// Reconfigure the live graph to play a source of `channelCount` channels in `layout` end to end.
    ///
    /// The graph's source width takes the file's OWN layout (`engineFormat(channelCount:layout:sampleRate:)`, F1): its
    /// channels in its own order, so the resampler converts the rate only and the roles read from the
    /// file's labels name the right slots. Mono and stereo keep today's formats, and a file wider than the
    /// engine carries plays through the stereo fallback.
    ///
    /// This is the spike-validated lifecycle that re-formats a SINGLE running engine without a crash or a
    /// silent downmix. It must run OFF the audio thread (it stops the player, removes taps, reconnects
    /// nodes, resizes the per-channel analyzers, and re-starts the engine). It is a no-op when the graph
    /// already plays that format — rate, channel count AND layout — so the stereo path is byte-for-byte
    /// unchanged, and a 5.1 file after a 5.1 file in another order still re-lays the graph.
    ///
    /// Both custom AU nodes are re-formatted together (Sprint 5b M3-3): the chain
    /// `player -> effectsAU -> spatialAU -> mainMixer -> output` is reconnected with the effects-AU
    /// edges at the source format (width N) and the spatial-AU output + mixer + output at the device
    /// boundary `deviceWidthFormat` resolves (M == N, or stereo when the device is narrower).
    ///
    /// The hard-won findings from the spike are baked in here:
    /// - The `mainMixerNode -> outputNode` reconnect (`reconnectGraph`) is MANDATORY: without it the
    ///   mixer silently downmixes to its own output width and only L/R carry signal for > 2ch.
    /// - Analyzer arrays are resized only while the taps are removed — never on the audio thread.
    /// - Production uses `engine.pause()` (device width is fixed; pause keeps attachments and is
    ///   lighter than stop). The offline harness can only change WIDTH via stop -> re-enable manual
    ///   rendering -> start, so `reconfigureGraph` detects manual-rendering mode and branches.
    ///
    /// - Parameters:
    ///   - channelCount: the source's channel count N.
    ///   - layout: the source's channel layout (`processingFormat.channelLayout`; nil when it reports none).
    func reconfigureGraph(channelCount: AVAudioChannelCount, layout: AVAudioChannelLayout?) {
        guard let engine = avEngine, let player = playerNode,
              let effects = effectsNode, let spatial = spatialAudioUnit else { return }

        // 1. Resolve the graph format, falling back to stereo, then aborting gracefully.
        guard let format = resolveReconfigureFormat(channelCount: channelCount, layout: layout,
                                                    sampleRate: currentGraphSampleRate)
        else {
            abortReconfigure(reason: "no usable format for \(channelCount)ch (stereo fallback also nil)")
            return
        }

        // 2. Same-format guard — keep the existing path 100% untouched until a real reconfigure.
        guard format != player.outputFormat(forBus: 0) else { return }

        // 3. Quiesce the audio thread: stop any streaming-resampler loop (bump generation + drop
        //    session so no in-flight buffer schedules onto the graph we're about to reconnect), then
        //    stop the player and remove every tap before touching nodes.
        stopEnhancedResampler()
        player.stop()
        removeSpectrumTap()

        // 4 + 6 + 8: pause (or offline stop), reconnect at the new format, then restart the engine.
        // 7. Resize analyzers while taps are removed (off the audio thread) — done inside the helper.
        // 9 + 10: reinstall taps + publish the new running state — done inside the helper.
        do {
            let nodes = ReconfigureGraphNodes(engine: engine, player: player, effects: effects, spatial: spatial)
            try applyReconfigure(nodes: nodes, format: format)
        } catch {
            // 8. engine.start() threw (an AU could not re-allocate render resources at this format):
            // transition to a safe state and log — never crash the app.
            abortReconfigure(reason: "engine.start() failed at \(format.channelCount)ch: \(error)")
        }
    }

    /// The sample rate the graph runs at (48 kHz today). Read from the live player output format so
    /// the reconfigured format keeps the rate stable across a format change.
    private var currentGraphSampleRate: Double {
        let rate = playerNode?.outputFormat(forBus: 0).sampleRate ?? 0
        return rate > 0 ? rate : 48000.0
    }

    /// The graph format for the source (F1: its own layout at the graph's rate), falling back to stereo
    /// for a file wider than the engine carries. Returns `nil` only if even the stereo fallback cannot be
    /// built (should never happen).
    private func resolveReconfigureFormat(channelCount: AVAudioChannelCount, layout: AVAudioChannelLayout?,
                                          sampleRate: Double) -> AVAudioFormat? {
        engineFormat(channelCount: channelCount, layout: layout, sampleRate: sampleRate)
            ?? multichannelFormat(for: 2, sampleRate: sampleRate)
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
        var analysis = tapAnalysis
        analysis.before = (0 ..< count).map { _ in
            SpectrumAnalyzer(sampleRate: sampleRate)
        }
        analysis.after = (0 ..< count).map { _ in
            SpectrumAnalyzer(sampleRate: sampleRate)
        }
        setTapAnalysis(analysis)
    }

    /// Pause (or, offline, stop) the engine, reconnect the two-AU chain at `format`, resize
    /// analyzers, restart, then reinstall taps and publish `.running`. Throws if `engine.start()`
    /// fails so the caller can land in a safe state.
    ///
    /// The device boundary is resolved by `deviceWidthFormat` (M2-d, §8½ C1) from the engine output
    /// node's negotiated width: M = N when the device takes every channel (the spatial AU is then a
    /// bit-exact identity route); stereo when it is narrower than a multichannel source — so a 5.1
    /// source on a stereo device reconnects the effects edges at N = 6 and the spatial output + mixer
    /// + output at 2, and the spatial AU folds 6 -> 2 (no naive mixer downmix).
    private func applyReconfigure(nodes: ReconfigureGraphNodes, format: AVAudioFormat) throws {
        let engine = nodes.engine
        // Device width M = min(N, deviceChannels). Resolved BEFORE any stop/re-enable so the output
        // node still reports the in-effect device width (the manual-rendering width when offline).
        let deviceFormat = deviceWidthFormat(engine: engine, sourceFormat: format)
        if engine.isInManualRenderingMode {
            // Offline: the manual-rendering format is immutable while running, so changing WIDTH
            // requires stop -> re-enable manual rendering at the new (device-width) format -> start.
            engine.stop()
            reconnectGraph(nodes: nodes, sourceFormat: format, deviceFormat: deviceFormat)
            resizeAnalyzers(to: format.channelCount, sampleRate: format.sampleRate)
            try engine.enableManualRenderingMode(.offline, format: deviceFormat,
                                                 maximumFrameCount: manualRenderingBlockSize)
            try engine.start()
        } else {
            // Live device: pause keeps attachments and is lighter than stop. The device width is
            // fixed, so reconnecting at the resolved formats + restart re-allocates both AUs.
            engine.pause()
            reconnectGraph(nodes: nodes, sourceFormat: format, deviceFormat: deviceFormat)
            resizeAnalyzers(to: format.channelCount, sampleRate: format.sampleRate)
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
