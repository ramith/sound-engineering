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
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

func fail(_ message: String) -> Never {
    print("VERIFY FAIL: \(message)")
    exit(1)
}

/// Reference box for handing an `AVAudioUnit.instantiate` result out of its `@Sendable`
/// completion into a synchronous `DispatchSemaphore.wait()` caller. `@unchecked Sendable`
/// because the completion is the sole writer and the caller reads only AFTER `gate.wait()`
/// returns — the semaphore's signal/wait pair orders the write before the read, so there is
/// no concurrent access.
final class InstantiateBox: @unchecked Sendable {
    var unit: AVAudioUnit?
    var error: Error?
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
let instantiateResult = InstantiateBox()
AVAudioUnit.instantiate(with: description, options: []) { unit, error in
    instantiateResult.unit = unit
    instantiateResult.error = error
    instantiateGate.signal()
}

instantiateGate.wait()

if let error = instantiateResult.error {
    fail("AVAudioUnit.instantiate errored: \(error)")
}

guard let auNode = instantiateResult.unit else {
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
// Implementation extracted to VerifyMultichannel.swift; orchestrated below.
// =====================================================================================

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
// Implementation extracted to VerifyLiveReconfigure.swift; orchestrated below.
// =====================================================================================

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
    // See instantiateAU(): the semaphore signal/wait provides the happens-before
    // ordering the compiler can't see across the completion closure.
    nonisolated(unsafe) var unit: AVAudioUnit?
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
    // internalRenderBlock is a non-optional AUInternalRenderBlock — its existence is
    // guaranteed by the type system at attach, so no runtime nil check is meaningful
    // here (the former `== nil` guard was always false). Merely accessing it exercises
    // the getter, which is the smoke test we want.
    _ = spatialNode.auAudioUnit.internalRenderBlock

    print("M3-2 PASS: SpatialRendererAU registered + instantiated; auAudioUnit class = \(className)")
    return true
}

if !verifySpatialRendererRegistration() {
    print("VERIFY FAIL: SpatialRendererAU (M3-2) smoke check failed")
    exit(1)
}

print("ALL M3-2 CHECKS PASSED — SpatialRendererAU registers + instantiates with a non-nil render block")

// =====================================================================================
// M3-3 — FULL two-AU device-boundary graph (player -> effects -> spatial -> mixer -> output).
// Implementation extracted to VerifyTwoAUGraph.swift; orchestrated below.
// =====================================================================================

if !verifyM3p3() {
    print("VERIFY FAIL: two-AU graph (M3-3) check failed")
    exit(1)
}

print("ALL M3-3 CHECKS PASSED — full player->effects->spatial->mixer->output graph carries N channels "
    + "end to end with the spatial AU correctly inserted as the device boundary, and the spatial AU is "
    + "a bit-exact identity route (M == N) at {2,6,8}ch")

// =====================================================================================
// M2-d — file-load device-width resolution (M = min(N, deviceChannels)).
// Implementation extracted to VerifyDeviceWidth.swift; orchestrated below.
// =====================================================================================

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
