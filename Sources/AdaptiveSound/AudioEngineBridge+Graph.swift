import Accelerate
import AVFoundation
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
        completion: @escaping (Bool) -> Void
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
    /// - `spatialAU -> mainMixer -> output` is connected at the DEVICE width M.
    ///
    /// For M3 the device width M == source width N (`format`), so the spatial AU is a bit-exact
    /// identity route and the mixer runs at the device width (a no-op fold). The mixer->output
    /// reconnect is the spike's mandatory line (otherwise the mixer silently downmixes to its own
    /// output width). Stereo (N == 2) is byte-identical to the pre-M3-3 single-AU path.
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

        // Device width M (the spatial AU output, mixer, and output). The spatial AU derives its
        // in/out counts from these negotiated bus formats in allocateRenderResources.
        // TODO(M3/S4): M = min(sourceN, deviceChannels); device<N -> binaural (S4). For M3,
        // M = N (= `format`) so the spatial AU is an identity route and the chain is bit-exact.
        let deviceFormat = format
        engine.connect(spatial, to: engine.mainMixerNode, format: deviceFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: deviceFormat)
    }

    /// Pre-allocate the spectrum analyzer, loudness meter, and per-channel monitoring analyzers off
    /// the audio thread (vDSP_create_fftsetup allocates), keyed to the mixer's output sample rate.
    private func allocateAnalysisState(engine: AVAudioEngine, format: AVAudioFormat) {
        let mixerSampleRate = Float(engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)
        let sampleRate = mixerSampleRate > 0 ? mixerSampleRate : 48000.0
        spectrumAnalyzer = SpectrumAnalyzer(fftSize: SpectrumConstants.fftSize, sampleRate: sampleRate)
        loudnessMeter = loudnessMeterCreate(Double(sampleRate))

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
        mixer.installTap(onBus: 0,
                         bufferSize: AVAudioFrameCount(SpectrumConstants.fftSize),
                         format: mixerFormat)
        { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            // --- AUDIO THREAD --- Access only pre-allocated state through the analyzer pointer.
            guard let analyzer = self?.spectrumAnalyzer else { return }
            let abl = buffer.mutableAudioBufferList
            analyzer.processTapBuffer(
                abl,
                frameCount: buffer.frameLength,
                channelCount: buffer.format.channelCount
            )

            // Feed the BS.1770-5 loudness meter from the same buffer (non-interleaved).
            if let meter = self?.loudnessMeter, let channels = buffer.floatChannelData {
                let left = channels[0]
                let right = buffer.format.channelCount >= 2 ? channels[1] : channels[0]
                loudnessMeterAddStereo(meter, left, right, buffer.frameLength)
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
                          format: playerFormat)
        { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
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
                               format: auFormat)
        { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
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
