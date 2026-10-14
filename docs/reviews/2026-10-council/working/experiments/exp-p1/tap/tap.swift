import AVFoundation
// OFFLINE manual rendering only (no device I/O): what frame counts does a 4096-frame tap request deliver?
for fs in [44100.0, 48000.0, 96000.0, 192000.0] {
    let engine = AVAudioEngine()
    let fmt = AVAudioFormat(standardFormatWithSampleRate: fs, channels: 2)!
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: fmt)
    var sizes: [AVAudioFrameCount: Int] = [:]
    let lock = NSLock()
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: engine.mainMixerNode.outputFormat(forBus: 0)) { buf, _ in
        lock.lock(); sizes[buf.frameLength, default: 0] += 1; lock.unlock()
    }
    let src = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fs * 3))!
    src.frameLength = src.frameCapacity
    player.scheduleBuffer(src, completionHandler: nil)
    try! engine.start(); player.play()
    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var rendered = 0
    while rendered < Int(fs * 2) { _ = try! engine.renderOffline(512, to: out); rendered += 512 }
    Thread.sleep(forTimeInterval: 0.3)
    lock.lock(); print("fs \(Int(fs)): tap buffer frameLength histogram \(sizes.sorted { $0.key < $1.key })"); lock.unlock()
    engine.stop()
}
