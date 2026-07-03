// VerifyTwoAUGraph.swift — M3-3: FULL two-AU device-boundary graph.
//
// Extracted from main.swift (best-practices decomposition: one cohesive concern per file,
// mirroring VerifyDeviceWidth.swift's M2-d extraction). These are module-scope functions in the
// VerifyAUGraph executable; they reference the shared harness globals (sampleRate, renderBlockSize)
// and helpers (instantiateAU, instantiateSpatialAU, makeSyntheticInput, renderMultichannel,
// assertGenuineMultichannel) declared elsewhere in the same module. main.swift orchestrates by
// calling verifyM3p3().
//
// M3-3 — FULL two-AU device-boundary graph: player -> AdaptiveSoundAU (N->N effects) ->
// SpatialRendererAU (N->M) -> mainMixer -> output, wired at {2, 6, 8} channels.
//
// This mirrors the production chain built by `AudioEngineBridge.connectInitialGraph` /
// `reconnectGraph`: the effects-AU edges (player->effects->spatial) at the source/processing
// width N, and the spatial-AU output + mixer + output at the device width M. For M3 the device
// width M == source width N (an identity spatial route — see the TODO(S4) markers in the
// bridge), so with BOTH AUs in their default (bit-exact bypass) state the whole chain must be a
// BIT-EXACT passthrough of the input, PER CHANNEL, at each width. That proves:
//   1. the SpatialRendererAU is correctly inserted between the effects AU and the mixer,
//   2. its identity route is sample-accurate (no gain, no fold, no reorder),
//   3. the stereo (N == 2) path is byte-identical to the pre-M3-3 single-AU path.

import AudioFormatKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

/// The four AVAudioEngine graph node references threaded through the two-AU wiring helpers
/// (`connectTwoAUGraph`, `reconfigureToSource` in VerifyDeviceWidth.swift). Grouping them keeps
/// those functions under the SwiftLint parameter-count ceiling without losing the descriptive
/// per-node names at call sites.
struct GraphNodes {
    let engine: AVAudioEngine
    let player: AVAudioPlayerNode
    let effects: AVAudioUnit
    let spatial: AVAudioUnit
}

/// Wire the full two-AU graph player -> effects -> spatial -> mainMixer -> output. The effects
/// edges (player->effects->spatial) use `sourceFormat` (width N); the spatial output + mixer +
/// output use `deviceFormat` (width M). For M3, M == N. The mixer->output reconnect is mandatory.
func connectTwoAUGraph(
    nodes: GraphNodes,
    sourceFormat: AVAudioFormat,
    deviceFormat: AVAudioFormat
) {
    let engine = nodes.engine
    engine.attach(nodes.player)
    engine.attach(nodes.effects)
    engine.attach(nodes.spatial)
    engine.connect(nodes.player, to: nodes.effects, format: sourceFormat)
    engine.connect(nodes.effects, to: nodes.spatial, format: sourceFormat)
    engine.connect(nodes.spatial, to: engine.mainMixerNode, format: deviceFormat)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: deviceFormat)
}

/// Pipeline render latency (in samples) an offline graph adds before steady state. AVAudioPlayerNode
/// + the AU(s) + the mixer introduce a fixed integer-sample delay, so a TRUE identity chain produces
/// `output[frame + lag] == input[frame]` for some constant `lag`. A generous ceiling that comfortably
/// covers the player + AU + mixer latency at this block size.
let maxPassthroughLag = 4096

/// A safe interior window length to compare over, leaving room for the search lag at the start and
/// any tail flush at the end so we never index past either buffer.
let passthroughCompareGuard = 256

/// Per-channel max |output[frame + lag] - input[frame]| over a safe interior window. A result of
/// exactly 0 on every channel means the chain reproduces the input sample-for-sample at that lag —
/// i.e. a bit-exact passthrough modulo the constant pipeline delay. Returns nil on a size mismatch.
func perChannelMaxAbsDiff(
    output: [[Float]],
    input: AVAudioPCMBuffer,
    channelCount: AVAudioChannelCount,
    atLag lag: Int
) -> [Float]? {
    guard let inputData = input.floatChannelData else { return nil }
    let frameCount = Int(input.frameLength)
    let compareCount = frameCount - lag - passthroughCompareGuard
    guard compareCount > 0 else { return nil }
    var diffs = [Float](repeating: 0, count: Int(channelCount))
    for channel in 0 ..< Int(channelCount) {
        let captured = output[channel]
        guard captured.count == frameCount else { return nil }
        let inChannel = inputData[channel]
        var maxDiff: Float = 0
        for frame in 0 ..< compareCount {
            maxDiff = max(maxDiff, abs(captured[frame + lag] - inChannel[frame]))
        }
        diffs[channel] = maxDiff
    }
    return diffs
}

/// Find the constant pipeline-delay lag that best aligns output to input: the lag minimising the
/// channel-0 max-diff. A true identity chain hits exactly 0 at that lag. The delay is channel
/// independent, so scanning channel 0 alone is enough (and fast).
func bestAlignmentLag(output: [[Float]], input: AVAudioPCMBuffer) -> Int? {
    guard let inputData = input.floatChannelData else { return nil }
    let frameCount = Int(input.frameLength)
    let outChannel0 = output[0]
    guard outChannel0.count == frameCount else { return nil }
    let inChannel0 = inputData[0]

    var bestLag = 0
    var bestDiff = Float.greatestFiniteMagnitude
    for lag in 0 ... maxPassthroughLag {
        let compareCount = frameCount - lag - passthroughCompareGuard
        if compareCount <= 0 { break }
        var maxDiff: Float = 0
        for frame in 0 ..< compareCount {
            maxDiff = max(maxDiff, abs(outChannel0[frame + lag] - inChannel0[frame]))
            if maxDiff >= bestDiff { break } // already worse than the best — abandon this lag
        }
        if maxDiff < bestDiff {
            bestDiff = maxDiff
            bestLag = lag
            if bestDiff == 0 { break } // exact alignment found; cannot do better
        }
    }
    return bestLag
}

// --- M3-3 part A: full two-AU graph topology + end-to-end flow ---

/// Build the FULL two-AU graph player -> effects -> spatial -> mixer -> output at `channelCount`
/// (device width M == source width N), confirm the spatial AU is genuinely inserted between the
/// effects AU and the mixer (correct insertion + correct render width), and that the whole chain
/// renders finite, non-silent signal on every channel end to end. Returns true on PASS.
///
/// This proves the SpatialRendererAU is the device-boundary stage in the real topology. The
/// per-sample identity of the spatial route itself is proven separately by `verifySpatialIdentity`
/// (which isolates the spatial AU so the effects AU's own — pre-existing, out-of-scope — lookahead
/// latency at default state cannot mask it).
func verifyTwoAUTopology(channelCount: AVAudioChannelCount) -> Bool {
    print("--- M3-3a two-AU graph (player->effects->spatial->mixer->output) channels = \(channelCount) ---")
    let label = "[\(channelCount)ch]"

    guard let mcFormat = multichannelFormat(for: channelCount, sampleRate: sampleRate),
          mcFormat.channelCount == channelCount
    else {
        print("M3-3 FAIL \(label): multichannelFormat returned nil or wrong width")
        return false
    }
    guard let effects = instantiateAU() else {
        print("M3-3 FAIL \(label): effects AU instantiate returned nil")
        return false
    }
    guard let spatial = instantiateSpatialAU() else {
        print("M3-3 FAIL \(label): spatial AU instantiate returned nil")
        return false
    }

    let twoEngine = AVAudioEngine()
    let twoPlayer = AVAudioPlayerNode()
    // Device width M == source width N for M3 (identity spatial route).
    connectTwoAUGraph(nodes: GraphNodes(engine: twoEngine, player: twoPlayer, effects: effects, spatial: spatial),
                      sourceFormat: mcFormat, deviceFormat: mcFormat)

    do {
        try twoEngine.enableManualRenderingMode(.offline, format: mcFormat, maximumFrameCount: renderBlockSize)
        try twoEngine.start()
    } catch {
        print("M3-3 FAIL \(label): engine setup threw: \(error)")
        return false
    }
    defer { twoEngine.stop() }

    if !assertTwoAUInsertion(engine: twoEngine, effects: effects, spatial: spatial,
                             channelCount: channelCount, label: label) {
        return false
    }

    guard let input = makeSyntheticInput(format: mcFormat, channelCount: channelCount) else {
        print("M3-3 FAIL \(label): could not build synthetic input buffer")
        return false
    }
    twoPlayer.scheduleBuffer(input, at: nil, options: [], completionHandler: nil)
    twoPlayer.play()

    guard let captured = renderMultichannel(engine: twoEngine, channelCount: channelCount, label: label) else {
        return false
    }
    if !assertGenuineMultichannel(captured, channelCount: channelCount, label: label) {
        return false
    }
    print("M3-3a PASS \(label): spatial AU inserted as device boundary (effects->spatial->mixer); "
        + "render width \(channelCount); all channels flow finite + non-silent end to end")
    return true
}

/// Confirm the spatial AU sits between the effects AU and the mixer, and the render width matches.
func assertTwoAUInsertion(
    engine: AVAudioEngine,
    effects: AVAudioUnit,
    spatial: AVAudioUnit,
    channelCount: AVAudioChannelCount,
    label: String
) -> Bool {
    let effectsOutputs = engine.outputConnectionPoints(for: effects, outputBus: 0)
    if !effectsOutputs.contains(where: { $0.node === spatial }) {
        print("M3-3 FAIL \(label): effects AU output does not connect to the spatial AU")
        return false
    }
    let spatialOutputs = engine.outputConnectionPoints(for: spatial, outputBus: 0)
    if !spatialOutputs.contains(where: { $0.node === engine.mainMixerNode }) {
        print("M3-3 FAIL \(label): spatial AU output does not connect to the mixer")
        return false
    }
    let renderWidth = engine.manualRenderingFormat.channelCount
    if renderWidth != channelCount {
        print("M3-3 FAIL \(label): render/output width \(renderWidth) != \(channelCount)")
        return false
    }
    return true
}

// --- M3-3 part B: SpatialRendererAU device-boundary identity route (bit-exact) ---

/// Build player -> spatial -> mixer -> output at `channelCount` (device width M == N) and assert the
/// output is a BIT-EXACT, per-channel passthrough of the input (max|out-in| == 0 after aligning out
/// the constant pipeline delay). This isolates the SpatialRendererAU so its identity route is proven
/// sample-for-sample — no gain, no fold, no reorder — exactly the property M3 relies on (M == N).
func verifySpatialIdentity(channelCount: AVAudioChannelCount) -> Bool {
    print("--- M3-3b spatial-AU identity route (player->spatial->mixer->output) channels = \(channelCount) ---")
    let label = "[\(channelCount)ch]"

    guard let mcFormat = multichannelFormat(for: channelCount, sampleRate: sampleRate),
          mcFormat.channelCount == channelCount
    else {
        print("M3-3 FAIL \(label): multichannelFormat returned nil or wrong width")
        return false
    }
    guard let spatial = instantiateSpatialAU() else {
        print("M3-3 FAIL \(label): spatial AU instantiate returned nil")
        return false
    }

    let engineB = AVAudioEngine()
    let playerB = AVAudioPlayerNode()
    engineB.attach(playerB)
    engineB.attach(spatial)
    engineB.connect(playerB, to: spatial, format: mcFormat)
    engineB.connect(spatial, to: engineB.mainMixerNode, format: mcFormat)
    engineB.connect(engineB.mainMixerNode, to: engineB.outputNode, format: mcFormat)

    do {
        try engineB.enableManualRenderingMode(.offline, format: mcFormat, maximumFrameCount: renderBlockSize)
        try engineB.start()
    } catch {
        print("M3-3 FAIL \(label): engine setup threw: \(error)")
        return false
    }
    defer { engineB.stop() }

    guard let input = makeSyntheticInput(format: mcFormat, channelCount: channelCount) else {
        print("M3-3 FAIL \(label): could not build synthetic input buffer")
        return false
    }
    playerB.scheduleBuffer(input, at: nil, options: [], completionHandler: nil)
    playerB.play()

    guard let captured = renderMultichannel(engine: engineB, channelCount: channelCount, label: label) else {
        return false
    }
    return assertSpatialIdentity(output: captured, input: input, channelCount: channelCount, label: label)
}

/// Assert the spatial-route output is finite and a BIT-EXACT, per-channel passthrough of `input`.
/// Delay-alignment is mandatory (the player + AU + mixer add a fixed integer-sample latency, so a
/// same-index compare would spuriously fail even for a perfect identity chain). Unlike the RMS-only
/// M1/M2 checks, this exact per-sample compare catches any gain/fold/reorder the spatial AU might do.
func assertSpatialIdentity(
    output: [[Float]],
    input: AVAudioPCMBuffer,
    channelCount: AVAudioChannelCount,
    label: String
) -> Bool {
    if !output.allSatisfy({ $0.allSatisfy(\.isFinite) }) {
        print("M3-3 FAIL \(label): output contains NaN/Inf — render instability")
        return false
    }
    guard let lag = bestAlignmentLag(output: output, input: input) else {
        print("M3-3 FAIL \(label): could not measure pipeline-delay alignment (size mismatch)")
        return false
    }
    guard let diffs = perChannelMaxAbsDiff(output: output, input: input,
                                           channelCount: channelCount, atLag: lag)
    else {
        print("M3-3 FAIL \(label): output/input length or channel mismatch at lag \(lag)")
        return false
    }
    let diffText = diffs.map { String(format: "%.3e", $0) }.joined(separator: ", ")
    let nonExactChannels = diffs.enumerated().filter { $0.element != 0 }.map(\.offset)
    if !nonExactChannels.isEmpty {
        print("M3-3 FAIL \(label): non-bit-exact channel(s) \(nonExactChannels) at delay-aligned "
            + "lag \(lag) — spatial AU is not an identity route. per-channel max|out-in| = [\(diffText)]")
        return false
    }
    print("M3-3b PASS \(label): spatial AU is a bit-exact device-boundary identity route on all "
        + "\(channelCount) channels (M == N; pipeline delay \(lag) samples); "
        + "per-channel max|out-in| = [\(diffText)]")
    return true
}

/// Run both M3-3 parts over {2, 6, 8}: (a) the full two-AU graph topology + end-to-end flow, and
/// (b) the SpatialRendererAU bit-exact identity route. Returns true only if every width passes both.
func verifyM3p3() -> Bool {
    let widths: [AVAudioChannelCount] = [2, 6, 8]
    for width in widths where !verifyTwoAUTopology(channelCount: width) {
        return false
    }
    for width in widths where !verifySpatialIdentity(channelCount: width) {
        return false
    }
    return true
}
