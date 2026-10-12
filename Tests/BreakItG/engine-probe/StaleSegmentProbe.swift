// S10.8 G break-it (playback/shell lane) - an AVFoundation probe of the call sequence the Enhanced path
// makes on pause, then a scrub, then the next start. OFFLINE manual rendering only: it never opens an
// output device and plays nothing. Each step names the app code it mirrors.
//
//   swiftc Tests/BreakItG/engine-probe/StaleSegmentProbe.swift -o .build/stale-segment-probe
//   .build/stale-segment-probe        (exit 1 = the stale segment plays first)

import AVFoundation

enum ProbeError: Error {
    case setup
}

/// A buffer whose every sample is `value`, so the rendered output says which schedule is playing.
func constant(_ value: Float, frames: AVAudioFrameCount, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
          let channels = buffer.floatChannelData else { throw ProbeError.setup }
    buffer.frameLength = frames
    for channel in 0 ..< Int(format.channelCount) {
        for frame in 0 ..< Int(frames) {
            channels[channel][frame] = value
        }
    }
    return buffer
}

/// Renders one block and returns a sample from inside it.
func renderSample(_ engine: AVAudioEngine) throws -> Float {
    guard let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4800) else {
        throw ProbeError.setup
    }
    _ = try engine.renderOffline(4800, to: out)
    return out.floatChannelData?[0][100] ?? .nan
}

/// Returns whether the block after starting track B is still track A.
func run() throws -> Bool {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
        throw ProbeError.setup
    }
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4800)
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    try engine.start()

    // Track A plays (0.25 everywhere).
    try player.scheduleBuffer(constant(0.25, frames: 48000, format: format), at: nil)
    player.play()
    _ = try renderSample(engine)

    // Pause: AudioEngineBridge.stopEnhancedPlayback (player.stop if playing, engine.stop if running).
    if player.isPlaying {
        player.stop()
    }
    engine.stop()

    // Scrub while paused: seekEnhancedBestEffort (player.stop, scheduleSegment of the rest of A, play).
    player.stop()
    try player.scheduleBuffer(constant(0.25, frames: 24000, format: format), at: nil)
    player.play()
    print("after the paused scrub: engine running=\(engine.isRunning), player playing=\(player.isPlaying)")

    // The user then starts track B: startEnhancedPlayback (engine.start) + playFile
    // (player.stop ONLY if isPlaying, scheduleFile(B), play).
    if !engine.isRunning {
        try engine.start()
    }
    if player.isPlaying {
        player.stop()
    }
    try player.scheduleBuffer(constant(0.75, frames: 48000, format: format), at: nil) // track B
    player.play()
    let first = try renderSample(engine)
    let stale = abs(first - 0.25) < 0.01
    print(stale
        ? "BROKEN: the first block after starting B is track A (sample \(first)), queued by the paused scrub"
        : "HOLDS: track B plays first (sample \(first))")
    return stale
}

guard let stale = try? run() else {
    print("probe setup failed")
    exit(2)
}
exit(stale ? 1 : 0)
