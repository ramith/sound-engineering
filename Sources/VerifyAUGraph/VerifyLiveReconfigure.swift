// VerifyLiveReconfigure.swift — M2-c: LIVE reconfigure of a SINGLE running engine.
//
// Extracted from main.swift (best-practices decomposition: one cohesive concern per file,
// mirroring VerifyMultichannel.swift / VerifyDeviceWidth.swift). These are module-scope
// functions in the VerifyAUGraph executable; they reference the shared harness globals
// (sampleRate, renderBlockSize) and helpers (instantiateAU, makeSyntheticInput,
// renderMultichannel, assertGenuineMultichannel) declared elsewhere in the same module.
// main.swift orchestrates by calling verifyLiveReconfigure(); the EQ1b re-allocation check
// (VerifyEQReallocation.swift) reuses the same reconfigure dance (`reconfigureAndRender`).
//
// Unlike M2-b (a fresh engine per width), here ONE engine is re-widthed in place:
// stereo -> 6ch -> stereo. After each step the graph must render at the new width with genuine
// per-channel signal — proving the reconfigure lifecycle (stop player, remove taps, reconnect at
// the new format INCLUDING mixer->output, resize analyzers, restart) is crash-free and continuous.
//
// Offline caveat (from the spike): the manual-rendering format is immutable while the engine runs,
// so to change WIDTH offline the harness does stop -> enableManualRenderingMode(.offline, format:)
// -> start. This is exactly the branch `AudioEngineBridge.reconfigureGraph` takes when it detects
// `engine.isInManualRenderingMode`; production on real hardware uses `engine.pause()` instead
// (device width is fixed). The reconnect (player->AU, AU->mixer, mixer->output) and the synthetic
// per-channel-distinct input are shared with M2-b so the two checks exercise the same wiring.

import AudioFormatKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

/// The one running engine a reconfigure re-formats in place: player -> AU -> mainMixer -> output.
/// `make` attaches the nodes; every reconfigure (re)connects them at the step's format.
struct ReconfigurableGraph {
    let engine: AVAudioEngine
    let player: AVAudioPlayerNode
    let unit: AVAudioUnit

    static func make(unit: AVAudioUnit) -> Self {
        let graph = Self(engine: AVAudioEngine(), player: AVAudioPlayerNode(), unit: unit)
        graph.engine.attach(graph.player)
        graph.engine.attach(unit)
        return graph
    }
}

/// Re-format the SAME running `graph` to `channelCount` at `rate` (stop -> reconnect -> re-enable
/// manual rendering -> start, the offline format-change dance, which re-allocates the AU's render
/// resources), re-feed a synthetic per-channel input (`makeSyntheticInput`) and render it.
/// Returns the captured [channel][frame] output, or nil on any failure (a "`check` FAIL `label`"
/// line already printed). Shared by M2-c and the EQ1b re-allocation check.
///
/// This is the offline analogue of `reconfigureGraph`'s manual-rendering branch: the existing
/// connections are rebuilt at the new format (mixer->output included) before re-enabling.
func reconfigureAndRender(
    _ graph: ReconfigurableGraph,
    channelCount: AVAudioChannelCount,
    rate: Double = sampleRate,
    check: String
) -> [[Float]]? {
    let label = "[reconfig->\(channelCount)ch]"
    let engine = graph.engine

    guard let stepFormat = multichannelFormat(for: channelCount, sampleRate: rate),
          stepFormat.channelCount == channelCount
    else {
        print("\(check) FAIL \(label): multichannelFormat returned nil or wrong width")
        return nil
    }

    // Teardown for an offline FORMAT change: stop (player + engine), reconnect every edge at the
    // new format (mixer->output is the critical line), then re-enable manual rendering + start.
    graph.player.stop()
    engine.stop()
    engine.connect(graph.player, to: graph.unit, format: stepFormat)
    engine.connect(graph.unit, to: engine.mainMixerNode, format: stepFormat)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: stepFormat)

    do {
        try engine.enableManualRenderingMode(.offline, format: stepFormat, maximumFrameCount: renderBlockSize)
        try engine.start()
    } catch {
        print("\(check) FAIL \(label): re-enable manual rendering / start threw: \(error)")
        return nil
    }

    let renderWidth = engine.manualRenderingFormat.channelCount
    if renderWidth != channelCount {
        print("\(check) FAIL \(label): post-reconfigure render width \(renderWidth) != \(channelCount)")
        return nil
    }

    guard let input = makeSyntheticInput(format: stepFormat, channelCount: channelCount) else {
        print("\(check) FAIL \(label): could not build synthetic input buffer")
        return nil
    }
    graph.player.scheduleBuffer(input, at: nil, options: [], completionHandler: nil)
    graph.player.play()

    return renderMultichannel(engine: engine, channelCount: channelCount, label: label)
}

/// One step of the live reconfigure: re-width the SAME running `graph` and render
/// (`reconfigureAndRender`), then assert genuine N-channel flow. Returns true on PASS.
func reconfigureStep(_ graph: ReconfigurableGraph, channelCount: AVAudioChannelCount) -> Bool {
    let label = "[reconfig->\(channelCount)ch]"
    guard let captured = reconfigureAndRender(graph, channelCount: channelCount, check: "M2-c") else {
        return false
    }
    if !assertGenuineMultichannel(captured, channelCount: channelCount, label: label) {
        return false
    }
    print("M2-c PASS \(label): live reconfigure to \(channelCount)ch — width + per-channel signal OK")
    return true
}

/// Drive a single running engine through stereo -> 6ch -> stereo, asserting at each width. Returns
/// true only if every step passes (no crash, finite + non-silent per channel, correct width).
func verifyLiveReconfigure() -> Bool {
    print("--- M2-c live reconfigure: stereo -> 6 -> stereo (single running engine) ---")

    guard let unit = instantiateAU() else {
        print("M2-c FAIL: AU instantiate returned nil")
        return false
    }
    let graph = ReconfigurableGraph.make(unit: unit)
    defer { graph.engine.stop() }

    // The reconfigure sequence (stereo -> 6 -> stereo) on ONE engine instance.
    let widths: [AVAudioChannelCount] = [2, 6, 2]
    for width in widths where !reconfigureStep(graph, channelCount: width) {
        return false
    }
    print("M2-c PASS: stereo -> 6 -> stereo completed on one running engine, crash-free + continuous")
    return true
}
