// VerifyDeviceWidth.swift — M2-d: file-load device-width resolution (M = min(N, deviceChannels)).
//
// Extracted from main.swift (best-practices decomposition: one cohesive concern per file).
// These are module-scope functions in the VerifyAUGraph executable; they reference the shared
// harness globals (sampleRate, renderBlockSize) and helpers (instantiateAU, instantiateSpatialAU,
// connectTwoAUGraph) declared elsewhere in the same module. main.swift orchestrates by calling
// verifyM2d().
//
// The file-load trigger re-widths the graph to the SOURCE width N and (for the device-boundary
// edges) resolves M = min(N, deviceChannels). This mirrors `AudioEngineBridge.deviceWidthFormat`
// + `applyReconfigure`: a 5.1 file (N = 6) on a STEREO device (deviceChannels = 2) must process at
// N = 6 (effects-AU input + spatial-AU input) and render N->M = 2 at the spatial-AU output (mixer
// + output also at M = 2). We simulate the fixed stereo device with an offline manual-rendering
// width of 2, then run the offline reconfigure dance (the branch `applyReconfigure` takes when
// `isInManualRenderingMode`) to the 6ch source and assert the bus widths.
//
// Review finding TOOL-1 (RESOLVED, cluster F): the M = min(N, device) resolver was previously a
// hand-copied mirror here. It now lives once in AudioFormatKit.deviceWidthFormat, which BOTH the
// production bridge (AudioEngineBridge.deviceWidthFormat) and this gate call — so the gate can no
// longer test a stale copy that has drifted from production.

import AudioFormatKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

/// Build the two-AU graph offline at the simulated `deviceChannels` width, then run the offline
/// reconfigure dance to `sourceChannels` (effects edges at N; spatial output + mixer + output at
/// M = min(N, deviceChannels)). Asserts the negotiated bus widths match the M2-d contract.
func verifyDeviceWidthResolution(sourceChannels: AVAudioChannelCount,
                                 deviceChannels: AVAudioChannelCount) -> Bool {
    let label = "[N=\(sourceChannels), device=\(deviceChannels)]"
    print("--- M2-d device-width resolution \(label) (effects/spatial in = N; spatial out/device = min(N,device)) ---")

    guard let deviceFmt = multichannelFormat(for: deviceChannels, sampleRate: sampleRate),
          let sourceFmt = multichannelFormat(for: sourceChannels, sampleRate: sampleRate)
    else {
        print("M2-d FAIL \(label): could not build device/source formats")
        return false
    }
    guard let effects = instantiateAU(), let spatial = instantiateSpatialAU() else {
        print("M2-d FAIL \(label): AU instantiate returned nil")
        return false
    }

    let dwEngine = AVAudioEngine()
    let dwPlayer = AVAudioPlayerNode()
    defer { dwEngine.stop() }
    let nodes = GraphNodes(engine: dwEngine, player: dwPlayer, effects: effects, spatial: spatial)
    // 1. Build + start the graph at the simulated device width (the engine's fixed device width).
    connectTwoAUGraph(nodes: nodes, sourceFormat: deviceFmt, deviceFormat: deviceFmt)
    do {
        try dwEngine.enableManualRenderingMode(.offline, format: deviceFmt, maximumFrameCount: renderBlockSize)
        try dwEngine.start()
    } catch {
        print("M2-d FAIL \(label): initial device-width engine setup threw: \(error)")
        return false
    }

    // 2. Resolve M from the output node (the in-effect device width) BEFORE re-enabling, exactly as
    //    `applyReconfigure` does, then reconfigure to the 6ch source via the offline dance.
    let observedDeviceChannels = dwEngine.outputNode.outputFormat(forBus: 0).channelCount
    let resolvedDevice = deviceWidthFormat(sourceFormat: sourceFmt,
                                           deviceChannels: observedDeviceChannels)
    if !reconfigureToSource(nodes: nodes, sourceFormat: sourceFmt,
                            deviceFormat: resolvedDevice, label: label) {
        return false
    }

    return assertDeviceWidths(effects: effects, spatial: spatial, sourceChannels: sourceChannels,
                              expectedDeviceChannels: resolvedDevice.channelCount, label: label)
}

/// The offline reconfigure dance (stop -> reconnect at N/M -> re-enable at M -> start), mirroring
/// `applyReconfigure`'s manual-rendering branch. Effects edges at `sourceFormat` (N); spatial
/// output + mixer + output at `deviceFormat` (M).
func reconfigureToSource(
    nodes: GraphNodes,
    sourceFormat: AVAudioFormat,
    deviceFormat: AVAudioFormat,
    label: String
) -> Bool {
    let engine = nodes.engine
    nodes.player.stop()
    engine.stop()
    engine.connect(nodes.player, to: nodes.effects, format: sourceFormat)
    engine.connect(nodes.effects, to: nodes.spatial, format: sourceFormat)
    engine.connect(nodes.spatial, to: engine.mainMixerNode, format: deviceFormat)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: deviceFormat)
    do {
        try engine.enableManualRenderingMode(.offline, format: deviceFormat, maximumFrameCount: renderBlockSize)
        try engine.start()
    } catch {
        print("M2-d FAIL \(label): reconfigure to source width threw: \(error)")
        return false
    }
    return true
}

/// Assert the negotiated bus widths after the reconfigure: effects-AU input + spatial-AU input at
/// N, spatial-AU output + mixer + output at the expected device width M.
func assertDeviceWidths(
    effects: AVAudioUnit,
    spatial: AVAudioUnit,
    sourceChannels: AVAudioChannelCount,
    expectedDeviceChannels: AVAudioChannelCount,
    label: String
) -> Bool {
    let effectsIn = effects.inputFormat(forBus: 0).channelCount
    let effectsOut = effects.outputFormat(forBus: 0).channelCount
    let spatialIn = spatial.inputFormat(forBus: 0).channelCount
    let spatialOut = spatial.outputFormat(forBus: 0).channelCount

    if effectsIn != sourceChannels || effectsOut != sourceChannels || spatialIn != sourceChannels {
        print("M2-d FAIL \(label): processing width != N (\(sourceChannels)) — "
            + "effectsIn=\(effectsIn) effectsOut=\(effectsOut) spatialIn=\(spatialIn)")
        return false
    }
    if spatialOut != expectedDeviceChannels {
        print("M2-d FAIL \(label): spatial output width \(spatialOut) != device M \(expectedDeviceChannels)")
        return false
    }
    print("M2-d PASS \(label): effects in/out = \(effectsIn)/\(effectsOut), spatial in = \(spatialIn) (= N), "
        + "spatial out = \(spatialOut) (= M = min(N, device)); processes at N, renders at device width M")
    return true
}

/// Run the M2-d device-width matrix. Returns true only if every case passes.
func verifyM2d() -> Bool {
    // 5.1 source on a stereo device: N = 6, device = 2 -> M = min(6, 2) = 2.
    guard verifyDeviceWidthResolution(sourceChannels: 6, deviceChannels: 2) else { return false }
    // 5.1 source on a 7.1-capable device: N = 6, device = 8 -> M = min(6, 8) = 6 (M == N).
    guard verifyDeviceWidthResolution(sourceChannels: 6, deviceChannels: 8) else { return false }
    // Stereo source on a stereo device: N = 2, device = 2 -> M = 2 (the unchanged stereo path).
    guard verifyDeviceWidthResolution(sourceChannels: 2, deviceChannels: 2) else { return false }
    return true
}
