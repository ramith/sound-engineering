// VerifyAUGraph — headless integration check for the AU-in-the-live-graph path.
//
// `swift test` is unusable here (swift-testing macro skew), so this is a runnable
// executable (`swift run VerifyAUGraph`) that asserts, via AVAudioEngine OFFLINE manual
// rendering, three things:
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
// smoke test only — full in-graph N->M render wiring is M3-3 and is NOT exercised here.
// =====================================================================================

func verifySpatialRendererRegistration() -> Bool {
    print("--- M3-2 SpatialRendererAU register + instantiate smoke check ---")

    registerSpatialRendererAUSubclass()
    let spatialDescription = spatialRendererComponentDescription()

    let gate = DispatchSemaphore(value: 0)
    var instance: AVAudioUnit?
    var instantiateErr: Error?
    AVAudioUnit.instantiate(with: spatialDescription, options: []) { unit, error in
        instance = unit
        instantiateErr = error
        gate.signal()
    }
    gate.wait()

    if let error = instantiateErr {
        print("M3-2 FAIL: AVAudioUnit.instantiate errored: \(error)")
        return false
    }
    guard let spatialNode = instance else {
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
print("=== SUMMARY: M1 (stereo passthrough) PASS + M2-b (multichannel 2/6/8) PASS + "
    + "M2-c (live reconfigure stereo->6->stereo) PASS + M3-2 (SpatialRendererAU register) PASS ===")
exit(0)
