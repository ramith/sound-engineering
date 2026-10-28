// VerifyF1ChannelIdentity.swift — F1 (R1.1-B, the level-and-fold design §2 and §10): a multichannel source
// keeps every channel in its own slot through the production converter and the two-AU graph, whatever its
// layout and rate.
//
// The shipped bug: the graph's source format was derived from the channel COUNT (6 → MPEG 5.1 A, 8 → MPEG
// 7.1 A, anything else → stereo) and Apple's converter re-laid the file into it by label — so on the
// resampler route a WAVE 7.1 or MPEG 7.1 C file lost its back pair, an AAC / ALAC 5.1 file (C L R Ls Rs LFE)
// came out reordered, and 3-, 4-, 5- and 7-channel files kept only L and R. Now the graph carries the
// source's OWN layout (`AudioFormatKit.engineFormat(forSource:sampleRate:)`, the function the app's graph
// and the analysis pass both call), so the converter changes the rate only.
//
// For every layout in `f1Layouts` at 44.1, 48 and 96 kHz: a tone per channel (`f1ToneHz`) at −20 dBFS,
// converted to the engine format by `StreamingResampler` in the app's chunks (none at 48 kHz: the app
// plays such a file straight through), played through player -> effects -> spatial -> mixer -> output with
// the device as wide as the source (M == N), rendered offline. Each slot must carry its own channel's tone
// at its level (±0.05 dB) and every other channel's tone below −80 dB.

import AudioFormatKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

/// The per-channel level: −20 dBFS, far below the effects unit's safety limiter.
private let f1Level: Float = 0.1

/// The measured stretch of the 48 kHz render: past the converter's hold-back and the chain's latency,
/// 0.4 s — a whole number of cycles of every tone, so one DFT bin reads each with no leakage.
private let f1Window = 9600 ..< 28800

/// Design §10: each input on its own slot within ±0.05 dB, every other below −80 dB.
private let f1LevelToleranceDb = 0.05
private let f1LeakCeilingDb = -80.0

/// Channel `channel`'s tone: 300, 500, … 1700 Hz (multiples of 100 Hz: whole cycles in `f1Window`).
private func f1ToneHz(_ channel: Int) -> Double {
    300 + 200 * Double(channel)
}

/// A layout given by per-channel labels (tag `UseChannelDescriptions`), as a FLAC with a channel mask
/// that matches no tag reports it (the corpus's 7.0 file).
private func describedLayout(_ labels: [AudioChannelLabel]) -> AVAudioChannelLayout? {
    guard !labels.isEmpty else { return nil }
    let size = MemoryLayout<AudioChannelLayout>.size + (labels.count - 1) * MemoryLayout<AudioChannelDescription>.stride
    let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioChannelLayout>.alignment)
    defer { raw.deallocate() }
    raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
    let layout = raw.bindMemory(to: AudioChannelLayout.self, capacity: 1)
    layout.pointee.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions
    layout.pointee.mNumberChannelDescriptions = UInt32(labels.count)
    let descriptions = UnsafeMutableRawPointer(layout)
        .advanced(by: MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions) ?? 0)
        .assumingMemoryBound(to: AudioChannelDescription.self)
    for (index, label) in labels.enumerated() {
        descriptions[index] = AudioChannelDescription(mChannelLabel: label, mChannelFlags: [], mCoordinates: (0, 0, 0))
    }
    return AVAudioChannelLayout(layout: layout)
}

/// The layouts design §10 names: the shipped bug's cases, the 3/4/5/7-channel labelled ones (7 by
/// per-channel labels, as the corpus's FLAC reports it), and unlabelled 5 and 8 channels.
private let f1Layouts: [(name: String, layout: AVAudioChannelLayout?)] = [
    ("WAVE_7_1", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_WAVE_7_1)),
    ("MPEG_7_1_C", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_7_1_C)),
    ("AAC_5_1", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_AAC_5_1)),
    ("WAVE_5_0_B", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_WAVE_5_0_B)),
    ("MPEG_3_0_A (3)", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_3_0_A)),
    ("WAVE_4_0_B (4)", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_WAVE_4_0_B)),
    ("MPEG_5_0_A (5)", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_0_A)),
    ("7.0 by labels (7)", describedLayout([
        kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center,
        kAudioChannelLabel_RearSurroundLeft, kAudioChannelLabel_RearSurroundRight,
        kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround,
    ])),
    ("DiscreteInOrder|5", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 5)),
    ("DiscreteInOrder|8", AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 8)),
]

private let f1Rates: [Double] = [44100, 48000, 96000]

/// One second of a tone per channel in `format`.
private func f1Tones(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frames = AVAudioFrameCount(format.sampleRate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
          let data = buffer.floatChannelData else { return nil }
    buffer.frameLength = frames
    for channel in 0 ..< Int(format.channelCount) {
        let step = 2 * Double.pi * f1ToneHz(channel) / format.sampleRate
        for frame in 0 ..< Int(frames) {
            data[channel][frame] = f1Level * Float(sin(step * Double(frame)))
        }
    }
    return buffer
}

/// Frames `range` of `source`, as one chunk the app's reader hands the converter.
private func f1Chunk(of source: AVAudioPCMBuffer, frames range: Range<Int>) -> AVAudioPCMBuffer? {
    guard let input = source.floatChannelData,
          let piece = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: StreamingResampler.inputChunkFrames),
          let pieceData = piece.floatChannelData else { return nil }
    piece.frameLength = AVAudioFrameCount(range.count)
    for channel in 0 ..< Int(source.format.channelCount) {
        pieceData[channel].update(from: input[channel].advanced(by: range.lowerBound), count: range.count)
    }
    return piece
}

/// Append `chunk` to `whole` (same format). False when it does not fit.
private func f1Append(_ chunk: AVAudioPCMBuffer, to whole: AVAudioPCMBuffer) -> Bool {
    let length = Int(chunk.frameLength), at = Int(whole.frameLength)
    guard at + length <= Int(whole.frameCapacity), let from = chunk.floatChannelData,
          let into = whole.floatChannelData else { return false }
    for channel in 0 ..< Int(whole.format.channelCount) {
        into[channel].advanced(by: at).update(from: from[channel], count: length)
    }
    whole.frameLength += AVAudioFrameCount(length)
    return true
}

/// `source` at the engine format, as the app's player receives it: through the production converter in the
/// app's chunks, flushed — or as it is when the rates already match (the passthrough route).
private func f1ToEngine(_ source: AVAudioPCMBuffer, engineFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
    if source.format == engineFormat {
        return source
    }
    guard let resampler = StreamingResampler(from: source.format, to: engineFormat),
          let whole = AVAudioPCMBuffer(pcmFormat: engineFormat,
                                       frameCapacity: AVAudioFrameCount(engineFormat.sampleRate * 2))
    else { return nil }
    let chunk = Int(StreamingResampler.inputChunkFrames)
    var start = 0
    while true {
        let count = min(chunk, Int(source.frameLength) - start)
        guard let piece = f1Chunk(of: source, frames: start ..< start + count),
              let converted = try? resampler.convert(piece, inputEnded: count == 0),
              f1Append(converted.buffer, to: whole) else { return nil }
        start += count
        if converted.endOfStream {
            return whole
        }
    }
}

/// Amplitude of the tone at `frequency` in `samples` (48 kHz): one DFT bin over whole cycles.
private func f1Amplitude(_ samples: ArraySlice<Float>, frequency: Double) -> Double {
    var real = 0.0, imaginary = 0.0
    for (index, sample) in samples.enumerated() {
        let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
        real += Double(sample) * cos(phase)
        imaginary -= Double(sample) * sin(phase)
    }
    return 2 * (real * real + imaginary * imaginary).squareRoot() / Double(samples.count)
}

/// Each slot carries its own channel's tone at its level and no other channel's (design §10's tolerances).
/// Prints the worst level error and the worst leak; returns the verdict.
private func f1AssertSlots(_ captured: [[Float]], channels: Int, label: String) -> Bool {
    var worstLevel = 0.0, worstLeak = -Double.infinity, verdict = true
    for slot in 0 ..< channels {
        let window = captured[slot][f1Window]
        let levelDb = 20 * log10(f1Amplitude(window, frequency: f1ToneHz(slot)) / Double(f1Level))
        worstLevel = max(worstLevel, abs(levelDb))
        if !(abs(levelDb) <= f1LevelToleranceDb) {
            print("F1 FAIL \(label): slot \(slot) plays its own channel at \(String(format: "%.3f", levelDb)) dB")
            verdict = false
        }
        for other in 0 ..< channels where other != slot {
            let leak = max(f1Amplitude(window, frequency: f1ToneHz(other)), 1e-12)
            let leakDb = 20 * log10(leak / Double(f1Level))
            worstLeak = max(worstLeak, leakDb)
            if !(leakDb < f1LeakCeilingDb) {
                print("F1 FAIL \(label): channel \(other) reaches slot \(slot) at \(String(format: "%.1f", leakDb)) dB")
                verdict = false
            }
        }
    }
    if verdict {
        print("F1 PASS \(label): every channel in its own slot (worst level error "
            + "\(String(format: "%.4f", worstLevel)) dB; worst leak \(String(format: "%.1f", worstLeak)) dB)")
    }
    return verdict
}

/// One layout at one rate through the converter and the two-AU graph (M == N).
private func verifyF1(layoutName: String, layout: AVAudioChannelLayout, rate: Double) -> Bool {
    let channels = Int(layout.channelCount)
    let label = "[\(layoutName) @ \(Int(rate)) Hz]"
    let source = AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
    guard let graphFormat = engineFormat(forSource: source, sampleRate: sampleRate),
          Int(graphFormat.channelCount) == channels
    else {
        print("F1 FAIL \(label): no engine format at the source's width (\(channels))")
        return false
    }
    guard let tones = f1Tones(format: source), let played = f1ToEngine(tones, engineFormat: graphFormat) else {
        print("F1 FAIL \(label): could not build or convert the tones")
        return false
    }
    guard let effects = instantiateAU(), let spatial = instantiateSpatialAU() else {
        print("F1 FAIL \(label): AU instantiate returned nil")
        return false
    }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    connectTwoAUGraph(nodes: GraphNodes(engine: engine, player: player, effects: effects, spatial: spatial),
                      sourceFormat: graphFormat, deviceFormat: graphFormat)
    do {
        try engine.enableManualRenderingMode(.offline, format: graphFormat, maximumFrameCount: renderBlockSize)
        try engine.start()
    } catch {
        print("F1 FAIL \(label): engine setup threw: \(error)")
        return false
    }
    defer { engine.stop() }
    player.scheduleBuffer(played, at: nil, options: [], completionHandler: nil)
    player.play()
    guard let captured = renderMultichannel(engine: engine, channelCount: graphFormat.channelCount, label: label)
    else { return false }
    return f1AssertSlots(captured, channels: channels, label: label)
}

/// Every layout at every rate. Returns true only if all pass.
func verifyF1ChannelIdentity() -> Bool {
    print("--- F1 channel identity: each channel in its own slot, through the converter and the graph ---")
    var verdict = true
    for (name, layout) in f1Layouts {
        guard let layout else {
            print("F1 FAIL [\(name)]: the layout does not build")
            verdict = false
            continue
        }
        for rate in f1Rates where !verifyF1(layoutName: name, layout: layout, rate: rate) {
            verdict = false
        }
    }
    return verdict
}
