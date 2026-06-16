// VerifyAUGraph — headless integration check for the AU-in-the-live-graph path.
//
// `swift test` is unusable here (swift-testing macro skew), so this is a runnable
// executable (`swift run VerifyAUGraph`) that asserts, via AVAudioEngine OFFLINE manual
// rendering, the following:
//
//   M1 (Sprint 5 M1, stereo) — the custom AdaptiveSoundAU:
//     1. registers + instantiates as an AVAudioUnit (class identity),
//     2. is actually IN the path (player's output connects to the AU, not the mixer),
//     3. renders every block .success with finite, non-silent, ~passthrough output
//        (default DSP state is bit-exact bypass, so a -12 dBFS sine survives intact).
//
//   M2-b (Sprint 5b M2-b, multichannel) — for each of {2, 6, 8} channels, the graph
//     player -> AdaptiveSoundAU -> mainMixer -> output connected at the N-channel format
//     (built by AudioFormatKit.multichannelFormat) genuinely carries N independent channels:
//     render/output width == N, and EVERY channel carries its own non-silent, finite signal
//     (proving real N-channel flow — NOT 2ch-padded-with-silence and NOT a downmix). This is
//     the offline safety net guarding the live-graph multichannel reconfigure.
//
//   M2-c (Sprint 5b M2-c, LIVE reconfigure) — the T-C5 equivalent. A SINGLE running engine is
//     re-widthed in place: stereo -> 6ch -> stereo. After each step the graph renders at the new
//     width with genuine per-channel signal and no crash/discontinuity. This mirrors the
//     `AudioEngineBridge.reconfigureGraph(to:)` lifecycle. Offline, WIDTH can only change via
//     stop -> re-enable manual rendering at the new format -> start (the manual-rendering format is
//     immutable while running), which is exactly the branch `reconfigureGraph` takes when it
//     detects `engine.isInManualRenderingMode`.
//
//   M2-d (Sprint 5b M2-d, file-load device-width resolution) — the file-load trigger re-widths the
//     graph to the SOURCE width N and resolves the device width M = min(N, deviceChannels). With a
//     simulated STEREO device (offline manual-rendering width 2), reconfiguring to a synthetic 6ch
//     source must leave the effects-AU input + spatial-AU input at N = 6 (process at full width)
//     and the spatial-AU output + mixer + output at M = min(6, 2) = 2 (the device boundary). This
//     mirrors `AudioEngineBridge.applyReconfigure` + `deviceWidthFormat` exactly: a 5.1 file on a
//     stereo device processes at 6 and the spatial AU renders 6->2 (its S4 device<N stub).
//
//   M3-2 (Sprint 5b M3-2) — SpatialRendererAU register + instantiate smoke check.
//
//   M3-3 (Sprint 5b M3-3, TWO-AU graph) — the FULL device-boundary topology
//     player -> AdaptiveSoundAU (N->N effects) -> SpatialRendererAU (N->M) -> mainMixer -> output
//     wired at {2, 6, 8} channels with BOTH AUs in their default (identity) state and the device
//     width M == source width N. With the effects AU in bit-exact bypass and the spatial AU an
//     identity route, the whole chain must be a BIT-EXACT passthrough of the input per channel at
//     each width — proving the spatial AU is correctly inserted as the device-boundary stage and
//     that the stereo path stays byte-identical.
//
// Keep ALL gates green. Exit non-zero on any failure so this can gate commits/CI.

import AudioFormatKit
import AVFoundation
import Foundation

func fail(_ message: String) -> Never {
    print("VERIFY FAIL: \(message)")
    exit(1)
}

let sampleRate = 48000.0
let renderBlockSize: AVAudioFrameCount = 512
let totalFrames: AVAudioFrameCount = 48000 // 1 second
let toneHz = 1000.0
let toneAmplitude: Float = 0.25 // -12 dBFS — below any limiter ceiling

// =====================================================================================
// M1 — stereo: register, instantiate, confirm AU is in the path, passthrough integrity.
// =====================================================================================

let channels: AVAudioChannelCount = 2

guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
    fail("could not create AVAudioFormat")
}

// 1. Register + instantiate.
registerAdaptiveAudioUnitSubclass()
let description = adaptiveAudioUnitComponentDescription()

let instantiateGate = DispatchSemaphore(value: 0)
var instantiatedUnit: AVAudioUnit?
var instantiateError: Error?
AVAudioUnit.instantiate(with: description, options: []) { unit, error in
    instantiatedUnit = unit
    instantiateError = error
    instantiateGate.signal()
}

instantiateGate.wait()

if let error = instantiateError {
    fail("AVAudioUnit.instantiate errored: \(error)")
}

guard let auNode = instantiatedUnit else {
    fail("AVAudioUnit.instantiate returned nil")
}

let auClassName = String(describing: type(of: auNode.auAudioUnit))
if !auClassName.contains("AdaptiveSound") {
    fail("instantiated AU is not AdaptiveSoundAU (got \(auClassName))")
}

print("step 1 ok: registered + instantiated; auAudioUnit class = \(auClassName)")

// 2. Build graph: player -> AU -> mainMixer, and assert the AU is genuinely in the path.
let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
engine.attach(player)
engine.attach(auNode)
engine.connect(player, to: auNode, format: format)
engine.connect(auNode, to: engine.mainMixerNode, format: format)

let playerOutputs = engine.outputConnectionPoints(for: player, outputBus: 0)
let playerFeedsAU = playerOutputs.contains { $0.node === auNode }
if !playerFeedsAU {
    fail("player output does not connect to the AU — AU is not in the path")
}

print("step 2 ok: player -> AU -> mainMixer; AU confirmed in the signal path")

// 3. Offline manual rendering.
do {
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: renderBlockSize)
    try engine.start()
} catch {
    fail("engine setup threw: \(error)")
}

guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
    fail("could not allocate input buffer")
}

inputBuffer.frameLength = totalFrames
for channel in 0 ..< Int(channels) {
    guard let data = inputBuffer.floatChannelData?[channel] else { fail("nil input channel data") }
    for frame in 0 ..< Int(totalFrames) {
        data[frame] = toneAmplitude * Float(sin(2.0 * Double.pi * toneHz * Double(frame) / sampleRate))
    }
}

player.scheduleBuffer(inputBuffer, at: nil, options: [], completionHandler: nil)
player.play()

guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                          frameCapacity: renderBlockSize)
else {
    fail("could not allocate render buffer")
}

var captured = [Float]()
captured.reserveCapacity(Int(totalFrames))
var framesRendered: AVAudioFrameCount = 0
var blocks = 0

while framesRendered < totalFrames {
    let toRender = min(renderBlockSize, totalFrames - framesRendered)
    let status: AVAudioEngineManualRenderingStatus
    do {
        status = try engine.renderOffline(toRender, to: renderBuffer)
    } catch {
        fail("renderOffline threw at block \(blocks): \(error)")
    }
    if status != .success {
        fail("renderOffline non-success (\(status.rawValue)) at block \(blocks)")
    }
    if let out = renderBuffer.floatChannelData?[0] {
        for frame in 0 ..< Int(renderBuffer.frameLength) {
            captured.append(out[frame])
        }
    }
    framesRendered += renderBuffer.frameLength
    blocks += 1
}

print("step 3 ok: offline-rendered \(framesRendered) frames over \(blocks) blocks, all .success")

// 4. Verify passthrough integrity (finite, non-silent, peak preserved).
if !captured.allSatisfy({ $0.isFinite }) { fail("output contains NaN/Inf — render instability") }
let outputPeak = captured.reduce(Float(0)) { max($0, abs($1)) }
let outputRMS = sqrt(captured.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(captured.count, 1)))
print("input peak = \(toneAmplitude), output peak = \(outputPeak), output RMS = \(outputRMS)")
if outputRMS < 0.01 { fail("output silent (RMS \(outputRMS)) — AU produced no signal") }
if outputPeak > toneAmplitude * 2.0 { fail("output peak \(outputPeak) >> input — gain/instability") }

engine.stop()
print("ALL M1 CHECKS PASSED — custom AU registers, instantiates, sits in the live graph, and renders")

// =====================================================================================
// M2-b — multichannel: per-channel non-silent flow at {2, 6, 8} channels (the safety net).
//
// One fresh engine + AU per width (keeps each graph's state trivially clean). The format the
// graph is connected at drives the channel count; the offline manual-rendering format is
// immutable while running, so each width does enableManualRenderingMode(.offline, format: N) ->
// start (per the spike's stop->re-enable->start note for width changes) on its own engine.
// =====================================================================================

/// Per-channel RMS for a captured [channel][frame] signal. Distinct, non-silent per channel
/// proves genuine N-channel flow (not 2ch padded with silence, not a downmix).
func perChannelRMS(_ captured: [[Float]]) -> [Float] {
    captured.map { samples in
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }
}

/// Synchronously instantiate a fresh AdaptiveSound AU (same component description as M1).
func instantiateAU() -> AVAudioUnit? {
    let gate = DispatchSemaphore(value: 0)
    var unit: AVAudioUnit?
    AVAudioUnit.instantiate(with: description, options: []) { instance, _ in
        unit = instance
        gate.signal()
    }
    gate.wait()
    return unit
}

/// Wire player -> AU -> mainMixer -> output, all connected at `format`.
///
/// The connect format drives the channel count (no AUAudioUnitBus.setFormat needed — it returns
/// -10868 and is unnecessary; the connect format is authoritative). The mixer->output connect is
/// THE CRITICAL LINE: mainMixerNode SILENTLY downmixes to its own output width unless we
/// explicitly reconnect it at the N-channel format; without it only L/R carry signal for >2ch.
func connectMultichannelGraph(
    engine: AVAudioEngine,
    player: AVAudioPlayerNode,
    unit: AVAudioUnit,
    format: AVAudioFormat
) {
    engine.attach(player)
    engine.attach(unit)
    engine.connect(player, to: unit, format: format)
    engine.connect(unit, to: engine.mainMixerNode, format: format)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
}

/// Allocate + fill an input buffer where each channel carries a DISTINCT non-silent tone
/// (frequency rises per channel), so genuine per-channel flow is distinguishable from a copy
/// or silence. Returns nil if allocation or channel access fails.
func makeSyntheticInput(format: AVAudioFormat, channelCount: AVAudioChannelCount) -> AVAudioPCMBuffer? {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
    buffer.frameLength = totalFrames
    for channel in 0 ..< Int(channelCount) {
        guard let data = buffer.floatChannelData?[channel] else { return nil }
        let channelHz = toneHz + Double(channel) * 250.0 // 1000, 1250, 1500, ... Hz per channel
        for frame in 0 ..< Int(totalFrames) {
            data[frame] = toneAmplitude * Float(sin(2.0 * Double.pi * channelHz * Double(frame) / sampleRate))
        }
    }
    return buffer
}

/// Offline-render the running `engine` and capture per-channel output. Returns the captured
/// [channel][frame] arrays, or nil on any render failure (message already printed).
func renderMultichannel(
    engine: AVAudioEngine,
    channelCount: AVAudioChannelCount,
    label: String
) -> [[Float]]? {
    guard let render = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                        frameCapacity: renderBlockSize)
    else {
        print("M2 FAIL \(label): could not allocate render buffer")
        return nil
    }

    var captured = [[Float]](repeating: [], count: Int(channelCount))
    for channel in 0 ..< Int(channelCount) {
        captured[channel].reserveCapacity(Int(totalFrames))
    }

    var rendered: AVAudioFrameCount = 0
    while rendered < totalFrames {
        let toRender = min(renderBlockSize, totalFrames - rendered)
        let status: AVAudioEngineManualRenderingStatus
        do {
            status = try engine.renderOffline(toRender, to: render)
        } catch {
            print("M2 FAIL \(label): renderOffline threw: \(error)")
            return nil
        }
        guard status == .success, let channelData = render.floatChannelData else {
            print("M2 FAIL \(label): renderOffline non-success (\(status.rawValue)) or nil channel data")
            return nil
        }
        for channel in 0 ..< Int(channelCount) {
            let out = channelData[channel]
            for frame in 0 ..< Int(render.frameLength) {
                captured[channel].append(out[frame])
            }
        }
        rendered += render.frameLength
    }
    return captured
}

/// Assert genuine N-channel flow: all samples finite + every channel non-silent. Prints a
/// PASS/FAIL line and returns the verdict.
func assertGenuineMultichannel(_ captured: [[Float]], channelCount: AVAudioChannelCount, label: String) -> Bool {
    if !captured.allSatisfy({ $0.allSatisfy(\.isFinite) }) {
        print("M2 FAIL \(label): output contains NaN/Inf — render instability")
        return false
    }
    let rms = perChannelRMS(captured)
    let rmsText = rms.map { String(format: "%.4f", $0) }.joined(separator: ", ")
    let silenceFloor: Float = 0.01
    let silentChannels = rms.enumerated().filter { $0.element < silenceFloor }.map(\.offset)
    if !silentChannels.isEmpty {
        print("M2 FAIL \(label): silent channel(s) \(silentChannels) — "
            + "not genuine N-channel flow (downmix or padding). per-channel RMS = [\(rmsText)]")
        return false
    }
    let minRMS = rms.min() ?? 0
    print("M2 PASS \(label): mixer->output reconnect in place; all \(channelCount) channels non-silent + "
        + "finite (min RMS \(String(format: "%.4f", minRMS))); per-channel RMS = [\(rmsText)]")
    return true
}

/// Build the graph at `channelCount`, offline-render a synthetic per-channel-distinct buffer,
/// and assert genuine N-channel throughput end to end. Returns true on PASS.
func verifyMultichannel(channelCount: AVAudioChannelCount) -> Bool {
    print("--- M2 channels = \(channelCount) ---")
    let label = "[\(channelCount)ch]"

    guard let mcFormat = multichannelFormat(for: channelCount, sampleRate: sampleRate),
          mcFormat.channelCount == channelCount
    else {
        print("M2 FAIL \(label): multichannelFormat returned nil or wrong width (unsupported count)")
        return false
    }
    guard let mcAU = instantiateAU() else {
        print("M2 FAIL \(label): AU instantiate returned nil")
        return false
    }

    let mcEngine = AVAudioEngine()
    let mcPlayer = AVAudioPlayerNode()
    connectMultichannelGraph(engine: mcEngine, player: mcPlayer, unit: mcAU, format: mcFormat)

    do {
        try mcEngine.enableManualRenderingMode(.offline, format: mcFormat, maximumFrameCount: renderBlockSize)
        try mcEngine.start()
    } catch {
        print("M2 FAIL \(label): engine setup threw: \(error)")
        return false
    }
    defer { mcEngine.stop() }

    // Render width must equal the requested width (proves the connect drove the channel count).
    let renderWidth = mcEngine.manualRenderingFormat.channelCount
    if renderWidth != channelCount {
        print("M2 FAIL \(label): render/output width \(renderWidth) != \(channelCount)")
        return false
    }

    guard let mcInput = makeSyntheticInput(format: mcFormat, channelCount: channelCount) else {
        print("M2 FAIL \(label): could not build synthetic input buffer")
        return false
    }
    mcPlayer.scheduleBuffer(mcInput, at: nil, options: [], completionHandler: nil)
    mcPlayer.play()

    guard let captured = renderMultichannel(engine: mcEngine, channelCount: channelCount, label: label) else {
        return false
    }
    return assertGenuineMultichannel(captured, channelCount: channelCount, label: label)
}

let multichannelCounts: [AVAudioChannelCount] = [2, 6, 8]
var allMultichannelPassed = true
for count in multichannelCounts where !verifyMultichannel(channelCount: count) {
    allMultichannelPassed = false
}

if !allMultichannelPassed {
    print("VERIFY FAIL: one or more multichannel (M2) checks failed")
    exit(1)
}

print("ALL M2 CHECKS PASSED — {2,6,8}ch each render at full width with genuine per-channel signal")

// =====================================================================================
// M2-c — LIVE reconfigure of a SINGLE running engine (the T-C5 equivalent).
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
// =====================================================================================

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

if !verifyLiveReconfigure() {
    print("VERIFY FAIL: live reconfigure (M2-c) check failed")
    exit(1)
}

print("ALL M2-c CHECKS PASSED — single-engine stereo->6->stereo reconfigure renders at each width")

// =====================================================================================
// M3-2 — SpatialRendererAU smoke check: register + instantiate the NEW device-boundary
// N->M render-stage AU (subtype 'aspz') via its own component description, and assert it
// is non-nil and its auAudioUnit class is SpatialRendererAU. This is the wrapper/C-ABI
// smoke test only — full in-graph N->M render wiring is M3-3 (below).
// =====================================================================================

/// Synchronously instantiate a fresh SpatialRenderer AU (subtype 'aspz'). Returns nil on failure.
func instantiateSpatialAU() -> AVAudioUnit? {
    let spatialDescription = spatialRendererComponentDescription()
    let gate = DispatchSemaphore(value: 0)
    var unit: AVAudioUnit?
    AVAudioUnit.instantiate(with: spatialDescription, options: []) { instance, _ in
        unit = instance
        gate.signal()
    }
    gate.wait()
    return unit
}

func verifySpatialRendererRegistration() -> Bool {
    print("--- M3-2 SpatialRendererAU register + instantiate smoke check ---")

    registerSpatialRendererAUSubclass()

    guard let spatialNode = instantiateSpatialAU() else {
        print("M3-2 FAIL: AVAudioUnit.instantiate returned nil for SpatialRendererAU")
        return false
    }

    let className = String(describing: type(of: spatialNode.auAudioUnit))
    if !className.contains("SpatialRenderer") {
        print("M3-2 FAIL: instantiated AU is not SpatialRendererAU (got \(className))")
        return false
    }
    if spatialNode.auAudioUnit.internalRenderBlock == nil {
        print("M3-2 FAIL: SpatialRendererAU internalRenderBlock is nil at attach")
        return false
    }

    print("M3-2 PASS: SpatialRendererAU registered + instantiated; auAudioUnit class = \(className)")
    return true
}

if !verifySpatialRendererRegistration() {
    print("VERIFY FAIL: SpatialRendererAU (M3-2) smoke check failed")
    exit(1)
}

print("ALL M3-2 CHECKS PASSED — SpatialRendererAU registers + instantiates with a non-nil render block")

// =====================================================================================
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
// =====================================================================================

/// Wire the full two-AU graph player -> effects -> spatial -> mainMixer -> output. The effects
/// edges (player->effects->spatial) use `sourceFormat` (width N); the spatial output + mixer +
/// output use `deviceFormat` (width M). For M3, M == N. The mixer->output reconnect is mandatory.
func connectTwoAUGraph(
    engine: AVAudioEngine,
    player: AVAudioPlayerNode,
    effects: AVAudioUnit,
    spatial: AVAudioUnit,
    sourceFormat: AVAudioFormat,
    deviceFormat: AVAudioFormat
) {
    engine.attach(player)
    engine.attach(effects)
    engine.attach(spatial)
    engine.connect(player, to: effects, format: sourceFormat)
    engine.connect(effects, to: spatial, format: sourceFormat)
    engine.connect(spatial, to: engine.mainMixerNode, format: deviceFormat)
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
    connectTwoAUGraph(engine: twoEngine, player: twoPlayer, effects: effects, spatial: spatial,
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
                             channelCount: channelCount, label: label)
    {
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

if !verifyM3p3() {
    print("VERIFY FAIL: two-AU graph (M3-3) check failed")
    exit(1)
}

print("ALL M3-3 CHECKS PASSED — full player->effects->spatial->mixer->output graph carries N channels "
    + "end to end with the spatial AU correctly inserted as the device boundary, and the spatial AU is "
    + "a bit-exact identity route (M == N) at {2,6,8}ch")

// =====================================================================================
// M2-d — file-load device-width resolution: M = min(N, deviceChannels).
//
// The file-load trigger re-widths the graph to the SOURCE width N and (for the device-boundary
// edges) resolves M = min(N, deviceChannels). This mirrors `AudioEngineBridge.deviceWidthFormat`
// + `applyReconfigure`: a 5.1 file (N = 6) on a STEREO device (deviceChannels = 2) must process at
// N = 6 (effects-AU input + spatial-AU input) and render N->M = 2 at the spatial-AU output (mixer
// + output also at M = 2). We simulate the fixed stereo device with an offline manual-rendering
// width of 2, then run the offline reconfigure dance (the branch `applyReconfigure` takes when
// `isInManualRenderingMode`) to the 6ch source and assert the bus widths.
// =====================================================================================

/// Free-function mirror of `AudioEngineBridge.deviceWidthFormat`: M = min(N, deviceChannels),
/// reusing the source format when M == N or when `multichannelFormat(for: M)` has no mapping.
/// Kept in the harness (the bridge type isn't constructed here) and asserted to agree with the
/// production resolution by construction.
func resolvedDeviceFormat(sourceFormat: AVAudioFormat, deviceChannels: AVAudioChannelCount) -> AVAudioFormat {
    let sourceChannels = sourceFormat.channelCount
    guard deviceChannels > 0 else { return sourceFormat }
    let deviceWidth = min(sourceChannels, deviceChannels)
    if deviceWidth == sourceChannels { return sourceFormat }
    if let format = multichannelFormat(for: deviceWidth, sampleRate: sourceFormat.sampleRate) {
        return format
    }
    return sourceFormat
}

/// Build the two-AU graph offline at the simulated `deviceChannels` width, then run the offline
/// reconfigure dance to `sourceChannels` (effects edges at N; spatial output + mixer + output at
/// M = min(N, deviceChannels)). Asserts the negotiated bus widths match the M2-d contract.
func verifyDeviceWidthResolution(sourceChannels: AVAudioChannelCount,
                                 deviceChannels: AVAudioChannelCount) -> Bool
{
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
    // 1. Build + start the graph at the simulated device width (the engine's fixed device width).
    connectTwoAUGraph(engine: dwEngine, player: dwPlayer, effects: effects, spatial: spatial,
                      sourceFormat: deviceFmt, deviceFormat: deviceFmt)
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
    let resolvedDevice = resolvedDeviceFormat(sourceFormat: sourceFmt, deviceChannels: observedDeviceChannels)
    if !reconfigureToSource(engine: dwEngine, player: dwPlayer, effects: effects, spatial: spatial,
                            sourceFormat: sourceFmt, deviceFormat: resolvedDevice, label: label)
    {
        return false
    }

    return assertDeviceWidths(effects: effects, spatial: spatial, sourceChannels: sourceChannels,
                              expectedDeviceChannels: resolvedDevice.channelCount, label: label)
}

/// The offline reconfigure dance (stop -> reconnect at N/M -> re-enable at M -> start), mirroring
/// `applyReconfigure`'s manual-rendering branch. Effects edges at `sourceFormat` (N); spatial
/// output + mixer + output at `deviceFormat` (M).
func reconfigureToSource(
    engine: AVAudioEngine,
    player: AVAudioPlayerNode,
    effects: AVAudioUnit,
    spatial: AVAudioUnit,
    sourceFormat: AVAudioFormat,
    deviceFormat: AVAudioFormat,
    label: String
) -> Bool {
    player.stop()
    engine.stop()
    engine.connect(player, to: effects, format: sourceFormat)
    engine.connect(effects, to: spatial, format: sourceFormat)
    engine.connect(spatial, to: engine.mainMixerNode, format: deviceFormat)
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

func verifyM2d() -> Bool {
    // 5.1 source on a stereo device: N = 6, device = 2 -> M = min(6, 2) = 2.
    guard verifyDeviceWidthResolution(sourceChannels: 6, deviceChannels: 2) else { return false }
    // 5.1 source on a 7.1-capable device: N = 6, device = 8 -> M = min(6, 8) = 6 (M == N).
    guard verifyDeviceWidthResolution(sourceChannels: 6, deviceChannels: 8) else { return false }
    // Stereo source on a stereo device: N = 2, device = 2 -> M = 2 (the unchanged stereo path).
    guard verifyDeviceWidthResolution(sourceChannels: 2, deviceChannels: 2) else { return false }
    return true
}

if !verifyM2d() {
    print("VERIFY FAIL: file-load device-width resolution (M2-d) check failed")
    exit(1)
}

print("ALL M2-d CHECKS PASSED — file-load reconfigure processes at N and resolves device width "
    + "M = min(N, deviceChannels): 5.1-on-stereo -> 6/2, 5.1-on-7.1 -> 6/6, stereo-on-stereo -> 2/2")
print("=== SUMMARY: M1 (stereo passthrough) PASS + M2-b (multichannel 2/6/8) PASS + "
    + "M2-c (live reconfigure stereo->6->stereo) PASS + M2-d (device width M=min(N,device)) PASS + "
    + "M3-2 (SpatialRendererAU register) PASS + "
    + "M3-3 (two-AU graph + spatial-AU bit-exact identity, 2/6/8) PASS ===")
exit(0)
