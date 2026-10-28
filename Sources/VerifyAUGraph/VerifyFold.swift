// VerifyFold.swift — the BS.775 stereo fold in the offline graph (R1.1-B; level-and-fold §S1b, §S2, §10).
//
// FOLD-1: player -> effects -> spatial -> mixer -> output, a 5.1 source (L R C LFE Ls Rs, a tone per channel at
//   −20 dBFS) on a stereo device, a plan published through the spatial unit's C-ABI (asSpatialPublishPlan: lane 1's
//   BS.775 matrix over the output state's roles, the LFE omitted, trim 0, the −1 dBTP backstop). Each side carries
//   its front channel at 0 dB and the centre and its surround at −3.01 dB (±0.05), the other side's channels and the
//   LFE below −80 dB, and the backstop's meter reads no gain reduction.
// FOLD-2: M == N is bit-exact with the backstop bypassed (design §10's backstop row) — the spatial unit in the source's
//   own layout (F1: AAC 5.1, WAVE 7.1) with a fold published that the identity route must ignore.

import AudioDSP
import AudioFormatKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

private let foldToleranceDb = 0.05
private let foldLeakCeilingDb = -80.0
private let foldLevel: Float = 0.1
/// Past the converter-free start and the effects unit's and the backstop's look-ahead; 0.4 s of whole cycles.
private let foldWindow = 9600 ..< 28800

/// Channel `channel`'s tone: 300, 500, … Hz (whole cycles in `foldWindow`).
private func foldToneHz(_ channel: Int) -> Double {
    300 + 200 * Double(channel)
}

private func foldAmplitudeDb(_ samples: ArraySlice<Float>, channel: Int) -> Double {
    var real = 0.0, imaginary = 0.0
    for (index, sample) in samples.enumerated() {
        let phase = 2 * Double.pi * foldToneHz(channel) * Double(index) / sampleRate
        real += Double(sample) * cos(phase)
        imaginary -= Double(sample) * sin(phase)
    }
    let amplitude = 2 * (real * real + imaginary * imaginary).squareRoot() / Double(samples.count)
    return 20 * log10(max(amplitude, 1e-12) / Double(foldLevel))
}

/// One second of a tone per channel in `format`.
private func foldTones(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
          let data = buffer.floatChannelData else { return nil }
    buffer.frameLength = totalFrames
    for channel in 0 ..< Int(format.channelCount) {
        let step = 2 * Double.pi * foldToneHz(channel) / format.sampleRate
        for frame in 0 ..< Int(totalFrames) {
            data[channel][frame] = foldLevel * Float(sin(step * Double(frame)))
        }
    }
    return buffer
}

/// The output state of a 5.1 file (L R C LFE Ls Rs) on a stereo device of unknown transport.
private func foldOutputState51() -> AsOutputState {
    var output = AsOutputState()
    output.engineRateHz = sampleRate
    output.sourceChannels = 6
    output.outputChannels = 2
    let roles = [AsChannelRoleL, AsChannelRoleR, AsChannelRoleC, AsChannelRoleLfe, AsChannelRoleLs, AsChannelRoleRs]
    withUnsafeMutableBytes(of: &output.sourceRoles) { slots in
        for (slot, role) in roles.enumerated() {
            slots[slot] = UInt8(role.rawValue)
        }
    }
    return output
}

/// FOLD-1: what each side must carry, per source channel (dB; nil = absent).
private let foldExpected: [[Double?]] = [
    [0, nil, -3.0103, nil, -3.0103, nil], // L′: L, C, Ls
    [nil, 0, -3.0103, nil, nil, -3.0103], // R′: R, C, Rs
]

private func assertFoldSides(_ captured: [[Float]], label: String) -> Bool {
    var verdict = true
    for side in 0 ..< 2 {
        let window = captured[side][foldWindow]
        for channel in 0 ..< 6 {
            let level = foldAmplitudeDb(window, channel: channel)
            if let expected = foldExpected[side][channel] {
                if !(abs(level - expected) <= foldToleranceDb) {
                    print("FOLD-1 FAIL \(label): side \(side) carries channel \(channel) at "
                        + "\(String(format: "%.3f", level)) dB, expected \(expected)")
                    verdict = false
                }
            } else if !(level < foldLeakCeilingDb) {
                print("FOLD-1 FAIL \(label): channel \(channel) reaches side \(side) at \(String(format: "%.1f", level)) dB")
                verdict = false
            }
        }
    }
    return verdict
}

/// FOLD-1: the fold in the full graph, a plan through the C-ABI.
private func verifyFoldInGraph() -> Bool {
    let label = "[5.1 -> stereo]"
    print("--- FOLD-1 the BS.775 fold in the graph \(label) ---")
    guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A),
          let source = engineFormat(channelCount: 6, layout: layout, sampleRate: sampleRate),
          let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
          let tones = foldTones(format: source),
          let effects = instantiateAU(), let spatial = instantiateSpatialAU()
    else {
        print("FOLD-1 FAIL \(label): could not build the formats, tones or units")
        return false
    }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    connectTwoAUGraph(nodes: GraphNodes(engine: engine, player: player, effects: effects, spatial: spatial),
                      sourceFormat: source, deviceFormat: stereo)
    do {
        try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: renderBlockSize)
        try engine.start()
    } catch {
        print("FOLD-1 FAIL \(label): engine setup threw: \(error)")
        return false
    }
    defer { engine.stop() }

    let handle = Unmanaged.passUnretained(spatial.auAudioUnit).toOpaque()
    var output = foldOutputState51()
    var plan = AsTrackPlan()
    plan.version = UInt32(AS_TRACK_PLAN_VERSION)
    plan.folds = 1
    plan.lfeVariant = UInt8(AsLfeVariantOmit.rawValue)
    plan.foldTrimDb = 0
    guard asSpatialPublishPlan(handle, &plan, &output, UInt8(AsPlanEventFreshStart.rawValue)) else {
        print("FOLD-1 FAIL \(label): the spatial unit refused the plan")
        return false
    }
    player.scheduleBuffer(tones, at: nil, options: [], completionHandler: nil)
    player.play()
    guard let captured = renderMultichannel(engine: engine, channelCount: 2, label: label) else { return false }
    var verdict = assertFoldSides(captured, label: label)
    var state = AsFoldState()
    if !asSpatialFoldState(handle, &state) || !state.folding || !state.fromPlan || state.backstopPeakGrDb >= 0.01 {
        print("FOLD-1 FAIL \(label): read-out folding \(state.folding), from plan \(state.fromPlan), "
            + "backstop GR \(state.backstopPeakGrDb) dB")
        verdict = false
    }
    if verdict {
        print("FOLD-1 PASS \(label): L′ = L + 0.7071·C + 0.7071·Ls and R′ mirrored (±\(foldToleranceDb) dB), the LFE "
            + "omitted, nothing else below \(Int(foldLeakCeilingDb)) dB; backstop GR \(state.backstopPeakGrDb) dB")
    }
    return verdict
}

/// FOLD-2: M == N in the source's own layout is a bit-exact identity route, with a fold published.
private func verifyFoldBypassedAtFullWidth(layoutTag: AudioChannelLayoutTag, name: String) -> Bool {
    let label = "[\(name), M == N]"
    print("--- FOLD-2 the spatial unit at full width \(label): bit-exact, the backstop bypassed ---")
    guard let layout = AVAudioChannelLayout(layoutTag: layoutTag),
          let format = engineFormat(channelCount: layout.channelCount, layout: layout, sampleRate: sampleRate),
          let spatial = instantiateSpatialAU(),
          let input = makeSyntheticInput(format: format, channelCount: format.channelCount)
    else {
        print("FOLD-2 FAIL \(label): could not build the format, the unit or the input")
        return false
    }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.attach(spatial)
    engine.connect(player, to: spatial, format: format)
    engine.connect(spatial, to: engine.mainMixerNode, format: format)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
    do {
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: renderBlockSize)
        try engine.start()
    } catch {
        print("FOLD-2 FAIL \(label): engine setup threw: \(error)")
        return false
    }
    defer { engine.stop() }
    // A fold for this width, as if it played on a narrower device: the identity route must not apply it.
    var output = AsOutputState()
    output.engineRateHz = sampleRate
    output.sourceChannels = format.channelCount
    output.outputChannels = 2
    let handle = Unmanaged.passUnretained(spatial.auAudioUnit).toOpaque()
    _ = asSpatialPublishLayoutFold(handle, &output)
    player.scheduleBuffer(input, at: nil, options: [], completionHandler: nil)
    player.play()
    guard let captured = renderMultichannel(engine: engine, channelCount: format.channelCount, label: label) else {
        return false
    }
    return assertSpatialIdentity(output: captured, input: input, channelCount: format.channelCount, label: label)
}

/// Both fold checks. Returns true only if all pass.
func verifyFold() -> Bool {
    guard verifyFoldInGraph() else { return false }
    return verifyFoldBypassedAtFullWidth(layoutTag: kAudioChannelLayoutTag_AAC_5_1, name: "AAC 5.1")
        && verifyFoldBypassedAtFullWidth(layoutTag: kAudioChannelLayoutTag_WAVE_7_1, name: "WAVE 7.1")
}
