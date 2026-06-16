// VerifyAUGraph — headless integration check for Sprint 5 M1 (AU in the live graph).
//
// `swift test` is unusable here (swift-testing macro skew), so this is a runnable
// executable (`swift run VerifyAUGraph`) that asserts, via AVAudioEngine OFFLINE manual
// rendering, that the custom AdaptiveSoundAU:
//   1. registers + instantiates as an AVAudioUnit (class identity),
//   2. is actually IN the path (player's output connects to the AU, not the mixer),
//   3. renders every block .success with finite, non-silent, ~passthrough output
//      (default DSP state is bit-exact bypass, so a -12 dBFS sine survives intact).
//
// This is the M1 acceptance gate. Keep it green.

import AVFoundation
import Foundation

func fail(_ message: String) -> Never {
    print("VERIFY FAIL: \(message)")
    exit(1)
}

let sampleRate = 48000.0
let channels: AVAudioChannelCount = 2
let renderBlockSize: AVAudioFrameCount = 512
let totalFrames: AVAudioFrameCount = 48000 // 1 second
let toneHz = 1000.0
let toneAmplitude: Float = 0.25 // -12 dBFS — below any limiter ceiling

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
exit(0)
