import Accelerate
import AudioFormatKit
@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge graph construction + analysis taps (Sprint 5b, M3-3)

/// Two-AU graph construction (instantiate/attach/connect `player -> effectsAU -> spatialAU ->
/// mainMixer -> output`) and the analysis-tap install/remove, factored out of the core
/// `AudioEngineBridge` class body into a same-module extension to keep the class focused (SwiftLint
/// `type_body_length`). The members touched here (`avEngine`, `playerNode`, `dspAudioUnit`,
/// `spatialAudioUnit`, the analyzer arrays, the meter/analyzer handles, `graphState`, the
/// `tapInstalled` flags) are module-internal on the base class so this extension can reach them.
extension AudioEngineBridge {
    /// Instantiate the effects AU, then (nested) the spatial AU, then wire the full two-AU graph and
    /// finish initialization. Each `AVAudioUnit.instantiate` completion is delivered on an arbitrary
    /// queue (attach/connect do not require the main thread). `completion` is invoked exactly once.
    func instantiateAndBuildGraph(
        engine: AVAudioEngine,
        player: AVAudioPlayerNode,
        format: AVAudioFormat,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let effectsDescription = adaptiveAudioUnitComponentDescription()
        AVAudioUnit.instantiate(with: effectsDescription, options: []) { [weak self] effectsUnit, error in
            guard let self else { completion(false); return }
            guard let effectsUnit, error == nil else { completion(false); return }
            self.dspAudioUnit = effectsUnit
            engine.attach(effectsUnit)

            let spatialDescription = spatialRendererComponentDescription()
            AVAudioUnit.instantiate(with: spatialDescription, options: []) { [weak self] spatialUnit, error in
                guard let self else { completion(false); return }
                guard let spatialUnit, error == nil else { completion(false); return }
                self.spatialAudioUnit = spatialUnit
                engine.attach(spatialUnit)

                self.connectInitialGraph(engine: engine, player: player,
                                         effects: effectsUnit, spatial: spatialUnit, format: format)
                self.allocateAnalysisState(engine: engine, format: format)
                completion(true)
            }
        }
    }

    /// Wire the device-boundary two-AU chain at the initial stereo width.
    ///
    /// Chain: `player -> effectsAU -> spatialAU -> mainMixer -> output`.
    /// - `player -> effectsAU -> spatialAU` is connected at the SOURCE/processing width N.
    /// - `spatialAU -> mainMixer -> output` is connected at the DEVICE width M = min(N, deviceCh).
    ///
    /// The device width M is resolved by `deviceWidthFormat` (M3/S4 resolution): M = min(N,
    /// `engine.outputNode` channel count). At init N == 2 and the device is ≥ stereo, so M == N == 2
    /// — byte-identical to the pre-M3-3 single-AU path. The mixer->output reconnect is the spike's
    /// mandatory line (otherwise the mixer silently downmixes to its own output width).
    private func connectInitialGraph(
        engine: AVAudioEngine,
        player: AVAudioPlayerNode,
        effects: AVAudioUnit,
        spatial: AVAudioUnit,
        format: AVAudioFormat
    ) {
        // Source/processing width N: player -> effects -> spatial input.
        engine.connect(player, to: effects, format: format)
        engine.connect(effects, to: spatial, format: format)

        // Device width M = min(N, deviceChannels) (the spatial AU output, mixer, and output). The
        // spatial AU derives its in/out counts from these negotiated bus formats. When M < N the
        // spatial AU's S4 stub renders N->M; for M == N it is a bit-exact identity route.
        // TODO(S4): device<N -> binaural (the real fold lives on the spatial AU side).
        let deviceFormat = deviceWidthFormat(engine: engine, sourceFormat: format)
        engine.connect(spatial, to: engine.mainMixerNode, format: deviceFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: deviceFormat)
    }

    /// Resolve the device-boundary format (width M) for a source/processing format `sourceFormat`
    /// (width N): M = min(N, deviceChannels) where deviceChannels is the engine output node's
    /// negotiated channel count. This is the M3/S4 device-width choice that lets a 5.1 file on a
    /// stereo device process at N=6 and render N->M=2 at the spatial AU (its S4 device<N stub),
    /// instead of letting the mixer naively downmix.
    ///
    /// Falls back to `sourceFormat` (M == N) if the output node reports 0 channels (not yet
    /// negotiated) or if `multichannelFormat(for: M)` has no mapping for the resolved M — never
    /// returns a format wider than the source.
    func deviceWidthFormat(engine: AVAudioEngine, sourceFormat: AVAudioFormat) -> AVAudioFormat {
        // Thin wrapper over the shared AudioFormatKit resolver (F3 / TOOL-1): read the negotiated
        // device width from the output node, then delegate the M = min(N, device) + format-mapping
        // logic to the ONE implementation the VerifyAUGraph gate also uses — no drift.
        let deviceChannels = engine.outputNode.outputFormat(forBus: 0).channelCount
        return AudioFormatKit.deviceWidthFormat(sourceFormat: sourceFormat,
                                                deviceChannels: deviceChannels)
    }

    /// Pre-allocate the spectrum analyzer, loudness meter, and per-channel monitoring analyzers off
    /// the audio thread (vDSP_create_fftsetup allocates), keyed to the mixer's output sample rate.
    private func allocateAnalysisState(engine: AVAudioEngine, format: AVAudioFormat) {
        let mixerSampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let sampleRate = mixerSampleRate > 0 ? mixerSampleRate : 48000.0
        spectrumAnalyzer = SpectrumAnalyzer(fftSize: SpectrumConstants.fftSize, sampleRate: sampleRate)
        // Precondition: `loudnessMeter` is nil here. This runs only from initialize()'s graph build,
        // and the LEAK #1 re-init guard tears down (nils the meter wrapper AFTER removeSpectrumTap)
        // before any rebuild — so this assigns onto a nil field, never overwriting (and silently
        // destroying) a meter whose raw handle a live tap might still hold. The wrapper's deinit is
        // the backstop that frees the handle on teardown / abandonment.
        loudnessMeter = LoudnessMeterHandle(sampleRate: Double(sampleRate))

        // Per-channel monitoring analyzers (Sprint 5 M3) — one per channel of the graph format, for
        // the pre-DSP (player) and post-DSP (effects AU) tap points. N-channel by construction.
        let channelCount = Int(format.channelCount)
        beforeAnalyzers = (0 ..< channelCount).map { _ in
            SpectrumAnalyzer(fftSize: SpectrumConstants.fftSize, sampleRate: sampleRate)
        }
        afterAnalyzers = (0 ..< channelCount).map { _ in
            SpectrumAnalyzer(fftSize: SpectrumConstants.fftSize, sampleRate: sampleRate)
        }

        graphState = .running(channelCount: channelCount)
    }

    // MARK: - Spectrum tap

    /// Install the analysis taps: the Now-Playing spectrum + loudness meter on `mainMixerNode`,
    /// the per-channel "before" spectra on the player node (pre-DSP), and the per-channel "after"
    /// spectra on the EFFECTS AU output bus (post-DSP — NOT the mixer, which carries the device
    /// width M, and NOT the spatial AU, which renders the device-width signal).
    ///
    /// The tap blocks run on the audio thread (or a CoreAudio I/O thread). They may NOT allocate,
    /// lock, log, or call Obj-C/Swift runtime beyond indexed buffer access + Accelerate.
    func installSpectrumTap() {
        guard let engine = avEngine, !tapInstalled else { return }
        installMixerTap(on: engine.mainMixerNode)
        installBeforeTap()
        installAfterTap()
        tapInstalled = true
    }

    /// Now-Playing spectrum + BS.1770-5 loudness, both fed from the mixer output bus.
    private func installMixerTap(on mixer: AVAudioMixerNode) {
        let mixerFormat = mixer.outputFormat(forBus: 0)
        // Capture the loudness meter's RAW handle ONCE here (off the audio thread), NOT the class
        // wrapper: reading the `loudnessMeter` class property on the audio thread would incur an ARC
        // retain/release, which is forbidden on the RT tap. The captured value is a POD pointer. It
        // stays valid because removeSpectrumTap() always runs BEFORE the meter wrapper is dropped/
        // destroyed (constraint c), so this closure can never fire after the handle is freed.
        let meterHandle = loudnessMeter?.handle
        mixer.installTap(onBus: 0,
                         bufferSize: AVAudioFrameCount(SpectrumConstants.fftSize),
                         format: mixerFormat) { [weak self, meterHandle] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            // --- AUDIO THREAD --- Access only pre-allocated state through the analyzer pointer.
            guard let analyzer = self?.spectrumAnalyzer else { return }
            let abl = buffer.mutableAudioBufferList
            analyzer.processTapBuffer(
                abl,
                frameCount: buffer.frameLength,
                channelCount: buffer.format.channelCount
            )

            // Feed the BS.1770-5 loudness meter from the same buffer (non-interleaved).
            // S6 MC-1 (UI-only, tracked as ENH-002 in docs/product/known-issues.md): this UI
            // READOUT meter measures L/R only. It is CORRECT for the common stereo device width
            // (M == 2, where L/R IS every channel) and does NOT drive makeup gain — the audible
            // loudness normalization is the DSP kernel's own N-channel-weighted LoudnessModule
            // (S1/S2), not this tap. For a >2-channel DEVICE output the integrated LUFS shown reads
            // slightly low (surround energy unmeasured). A correct N-channel UI meter needs the
            // device-width BS.1770-5 weights (surround ×1.41, LFE excluded) configured on the meter
            // and all M planar channels fed here — deferred with the multichannel-output path (S4
            // binaural fold is DEFERRED) to avoid plumbing channel-layout weights into the RT tap
            // for an edge that is not yet a primary path.
            if let meterHandle, let channels = buffer.floatChannelData {
                let left = channels[0]
                let right = buffer.format.channelCount >= 2 ? channels[1] : channels[0]
                loudnessMeterAddStereo(meterHandle, left, right, buffer.frameLength)
            }
        }
    }

    /// Pre-DSP (BEFORE) tap on the player node — a different node from the mixer, so the
    /// one-tap-per-bus rule holds. Feeds the per-channel before analyzers (N-channel).
    private func installBeforeTap() {
        guard let player = playerNode else { return }
        let playerFormat = player.outputFormat(forBus: 0)
        player.installTap(onBus: 0,
                          bufferSize: AVAudioFrameCount(SpectrumConstants.fftSize),
                          format: playerFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            // --- AUDIO THREAD --- (only the weak load + indexed analyzer access)
            guard let beforeAnalyzers = self?.beforeAnalyzers else { return }
            let abl = buffer.mutableAudioBufferList
            let channels = min(beforeAnalyzers.count, Int(buffer.format.channelCount))
            for index in 0 ..< channels {
                beforeAnalyzers[index].processTapBuffer(abl, frameCount: buffer.frameLength, channel: index)
            }
        }
        beforeTapInstalled = true
    }

    /// Post-DSP (AFTER) tap on the AdaptiveSound EFFECTS AU output bus — deliberately NOT the mixer
    /// and NOT the spatial AU. The mixer carries the device width M (post spatial-render), so
    /// "after DSP" monitoring observes the effects AU's N-channel processed output.
    private func installAfterTap() {
        guard let effectsUnit = dspAudioUnit else { return }
        let auFormat = effectsUnit.outputFormat(forBus: 0)
        effectsUnit.installTap(onBus: 0,
                               bufferSize: AVAudioFrameCount(SpectrumConstants.fftSize),
                               format: auFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            // --- AUDIO THREAD --- (only the weak load + indexed analyzer access)
            guard let afterAnalyzers = self?.afterAnalyzers else { return }
            let abl = buffer.mutableAudioBufferList
            let channels = min(afterAnalyzers.count, Int(buffer.format.channelCount))
            for index in 0 ..< channels {
                afterAnalyzers[index].processTapBuffer(abl, frameCount: buffer.frameLength, channel: index)
            }
        }
        afterTapInstalled = true
    }

    func removeSpectrumTap() {
        guard let engine = avEngine, tapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        if beforeTapInstalled {
            playerNode?.removeTap(onBus: 0)
            beforeTapInstalled = false
        }
        if afterTapInstalled {
            dspAudioUnit?.removeTap(onBus: 0)
            afterTapInstalled = false
        }
        tapInstalled = false
    }
}
