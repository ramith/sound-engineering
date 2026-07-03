// VerifyMultichannel.swift — M2-b: multichannel per-channel non-silent flow at {2, 6, 8} channels.
//
// Extracted from main.swift (best-practices decomposition: one cohesive concern per file,
// mirroring VerifyDeviceWidth.swift / VerifyTwoAUGraph.swift). These are module-scope functions
// in the VerifyAUGraph executable; they reference the shared harness globals (sampleRate,
// renderBlockSize, totalFrames, toneHz, toneAmplitude, description) declared in main.swift.
// main.swift orchestrates by calling verifyMultichannel(channelCount:) over {2, 6, 8}.
//
// One fresh engine + AU per width (keeps each graph's state trivially clean). The format the
// graph is connected at drives the channel count; the offline manual-rendering format is
// immutable while running, so each width does enableManualRenderingMode(.offline, format: N) ->
// start (per the spike's stop->re-enable->start note for width changes) on its own engine.

import AudioFormatKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

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
    // The completion runs on an arbitrary queue, but gate.signal()→gate.wait()
    // establishes a happens-before edge, so the write is safely visible to the
    // return. nonisolated(unsafe) documents that the semaphore, not the compiler,
    // provides the ordering guarantee.
    nonisolated(unsafe) var unit: AVAudioUnit?
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
