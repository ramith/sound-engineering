// VerifyLiveReconfigure.swift — M2-c: LIVE reconfigure of a SINGLE running engine.
//
// Extracted from main.swift (best-practices decomposition: one cohesive concern per file,
// mirroring VerifyMultichannel.swift / VerifyDeviceWidth.swift). These are module-scope
// functions in the VerifyAUGraph executable; they reference the shared harness globals
// (sampleRate, renderBlockSize) and helpers (instantiateAU, makeSyntheticInput,
// renderMultichannel, assertGenuineMultichannel) declared elsewhere in the same module.
// main.swift orchestrates by calling verifyLiveReconfigure().
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

/// One step of the live reconfigure: re-enable manual rendering at `format` on the SAME running
/// `engine` (stop -> re-enable -> start, the offline width-change dance), re-feed a synthetic
/// per-channel input, render, and assert genuine N-channel flow. Returns true on PASS.
///
/// This is the offline analogue of `reconfigureGraph`'s manual-rendering branch: the existing
/// connections are rebuilt at the new format (mixer->output included) before re-enabling.
func reconfigureStep(
    engine: AVAudioEngine,
    player: AVAudioPlayerNode,
    unit: AVAudioUnit,
    channelCount: AVAudioChannelCount
) -> Bool {
    let label = "[reconfig->\(channelCount)ch]"

    guard let stepFormat = multichannelFormat(for: channelCount, sampleRate: sampleRate),
          stepFormat.channelCount == channelCount
    else {
        print("M2-c FAIL \(label): multichannelFormat returned nil or wrong width")
        return false
    }

    // Teardown for an offline WIDTH change: stop (player + engine), reconnect every edge at the
    // new format (mixer->output is the critical line), then re-enable manual rendering + start.
    player.stop()
    engine.stop()
    engine.connect(player, to: unit, format: stepFormat)
    engine.connect(unit, to: engine.mainMixerNode, format: stepFormat)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: stepFormat)

    do {
        try engine.enableManualRenderingMode(.offline, format: stepFormat, maximumFrameCount: renderBlockSize)
        try engine.start()
    } catch {
        print("M2-c FAIL \(label): re-enable manual rendering / start threw: \(error)")
        return false
    }

    let renderWidth = engine.manualRenderingFormat.channelCount
    if renderWidth != channelCount {
        print("M2-c FAIL \(label): post-reconfigure render width \(renderWidth) != \(channelCount)")
        return false
    }

    guard let input = makeSyntheticInput(format: stepFormat, channelCount: channelCount) else {
        print("M2-c FAIL \(label): could not build synthetic input buffer")
        return false
    }
    player.scheduleBuffer(input, at: nil, options: [], completionHandler: nil)
    player.play()

    guard let captured = renderMultichannel(engine: engine, channelCount: channelCount, label: label) else {
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
    let rcEngine = AVAudioEngine()
    let rcPlayer = AVAudioPlayerNode()
    rcEngine.attach(rcPlayer)
    rcEngine.attach(unit)
    defer { rcEngine.stop() }

    // The reconfigure sequence (stereo -> 6 -> stereo) on ONE engine instance.
    let widths: [AVAudioChannelCount] = [2, 6, 2]
    for width in widths where !reconfigureStep(engine: rcEngine, player: rcPlayer, unit: unit, channelCount: width) {
        return false
    }
    print("M2-c PASS: stereo -> 6 -> stereo completed on one running engine, crash-free + continuous")
    return true
}
