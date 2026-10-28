// VerifyDeviceWidth.swift — M2-d: file-load device-width resolution (M = N, or stereo on a narrower device).
//
// Extracted from main.swift (best-practices decomposition: one cohesive concern per file).
// These are module-scope functions in the VerifyAUGraph executable; they reference the shared
// harness globals (sampleRate, renderBlockSize) and helpers (instantiateAU, instantiateSpatialAU,
// connectTwoAUGraph) declared elsewhere in the same module. main.swift orchestrates by calling
// verifyM2d().
//
// The file-load trigger re-formats the graph to the SOURCE (its own layout, F1) and resolves the device
// boundary: M = N when the device takes every channel; stereo when it is narrower than a multichannel
// source, whatever its width (R1.1-B §8½ C1: fold to stereo, never keep the first M channels); a mono or
// stereo source keeps M = min(N, device). This mirrors `AudioEngineBridge.deviceWidthFormat` +
// `applyReconfigure`: a 5.1 file (N = 6) on a STEREO device must process at N = 6 (effects-AU input +
// spatial-AU input) and render N->M = 2 at the spatial-AU output (mixer + output also at M = 2). We
// simulate the fixed device with an offline manual-rendering width, then run the offline reconfigure dance
// (the branch `applyReconfigure` takes when `isInManualRenderingMode`) to the source and assert the bus
// widths against the expected M stated per case (never the resolver's own answer read back).
//
// Review finding TOOL-1 (RESOLVED, cluster F): the M = min(N, device) resolver was previously a
// hand-copied mirror here. It now lives once in AudioFormatKit.deviceWidthFormat, which BOTH the
// production bridge (AudioEngineBridge.deviceWidthFormat) and this gate call — so the gate can no
// longer test a stale copy that has drifted from production.

import AudioFormatKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

/// A device of `channels` channels: the standard format for mono and stereo, unlabelled discrete wider.
private func simulatedDeviceFormat(channels: AVAudioChannelCount) -> AVAudioFormat? {
    if channels <= 2 {
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
    }
    return AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)
        .map { AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: $0) }
}

/// Build the two-AU graph offline at the simulated `deviceChannels` width, then run the offline
/// reconfigure dance to a source in `sourceLayout` (effects edges at N, the source's own format; spatial
/// output + mixer + output at the resolved device boundary). Asserts the negotiated bus widths, with the
/// boundary at `expectedDeviceChannels`.
func verifyDeviceWidthResolution(sourceLayout: AudioChannelLayoutTag,
                                 deviceChannels: AVAudioChannelCount,
                                 expectedDeviceChannels: AVAudioChannelCount) -> Bool {
    let sourceChannels = sourceLayout & 0xFFFF
    let label = "[N=\(sourceChannels), device=\(deviceChannels)]"
    print("--- M2-d device-width resolution \(label) (effects/spatial in = N; spatial out = "
        + "\(expectedDeviceChannels)) ---")

    guard let deviceFmt = simulatedDeviceFormat(channels: deviceChannels),
          let sourceFmt = engineFormat(channelCount: sourceChannels,
                                       layout: AVAudioChannelLayout(layoutTag: sourceLayout),
                                       sampleRate: sampleRate)
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
                              expectedDeviceChannels: expectedDeviceChannels, label: label)
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
        + "spatial out = \(spatialOut) (= M); processes at N, renders at the device boundary M")
    return true
}

/// One M2-d case: a source layout on a device of `device` channels, rendered at `expected` channels.
private struct DeviceWidthCase {
    let source: AudioChannelLayoutTag
    let device: AVAudioChannelCount
    let expected: AVAudioChannelCount
}

/// Run the M2-d device-width matrix. Returns true only if every case passes.
func verifyM2d() -> Bool {
    let cases = [
        DeviceWidthCase(source: kAudioChannelLayoutTag_MPEG_5_1_A, device: 2, expected: 2), // 5.1 on stereo: folds
        DeviceWidthCase(source: kAudioChannelLayoutTag_MPEG_5_1_A, device: 8, expected: 6), // 5.1 on 7.1: M == N
        DeviceWidthCase(source: kAudioChannelLayoutTag_Stereo, device: 2, expected: 2), // the unchanged stereo path
        // 7.1 on a 5.1 device: folds to stereo, never keeps the first six (C1).
        DeviceWidthCase(source: kAudioChannelLayoutTag_MPEG_7_1_A, device: 6, expected: 2),
        // 3.0 on stereo: plays at 3 and folds to 2 (before F1: a stereo graph).
        DeviceWidthCase(source: kAudioChannelLayoutTag_MPEG_3_0_A, device: 2, expected: 2),
        // AAC-order 5.1 on a 5.1 device: its own format, M == N.
        DeviceWidthCase(source: kAudioChannelLayoutTag_AAC_5_1, device: 6, expected: 6),
    ]
    for each in cases where !verifyDeviceWidthResolution(sourceLayout: each.source, deviceChannels: each.device,
                                                         expectedDeviceChannels: each.expected) {
        return false
    }
    return true
}
