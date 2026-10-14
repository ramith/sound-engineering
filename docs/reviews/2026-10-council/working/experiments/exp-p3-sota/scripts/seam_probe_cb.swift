// Does each completion type fire in offline manual rendering, and at which rendered frame?
import AVFAudio
import Foundation
let rate = 48000.0
let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
let urlA = URL(fileURLWithPath: CommandLine.arguments[1] + "/A.wav")
for cb in [AVAudioPlayerNodeCompletionCallbackType.dataConsumed, .dataRendered, .dataPlayedBack] {
    let engine = AVAudioEngine(); let player = AVAudioPlayerNode()
    engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: fmt)
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 512)
    try! engine.start()
    let fileA = try! AVAudioFile(forReading: urlA)
    let rendered = UnsafeMutablePointer<Int>.allocate(capacity: 1); rendered.pointee = 0
    let firedAt = UnsafeMutablePointer<Int>.allocate(capacity: 1); firedAt.pointee = -1
    player.scheduleFile(fileA, at: nil, completionCallbackType: cb) { _ in firedAt.pointee = rendered.pointee }
    player.play()
    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
    while rendered.pointee < Int(fileA.length) + 96000 {
        _ = try! engine.renderOffline(512, to: out); rendered.pointee += Int(out.frameLength)
        Thread.sleep(forTimeInterval: 512.0 / rate)
    }
    print("cb=\(cb.rawValue): file length \(fileA.length); completion fired at rendered frame \(firedAt.pointee) (-1 = never)")
    engine.stop()
}
