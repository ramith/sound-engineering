// Exp F: does AVAudioPlayerNode.volume apply when the player feeds EFFECT nodes before the mixer
// (production: player -> effectsAU -> spatialAU -> mainMixer)? And is a volume change ramped?
import AVFAudio
import Foundation
let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
func run(throughEffects: Bool, volume: Float, changeMidway: Bool) -> [Float] {
    let engine = AVAudioEngine(); let player = AVAudioPlayerNode()
    engine.attach(player)
    if throughEffects {
        let e1 = AVAudioUnitEQ(numberOfBands: 1); let e2 = AVAudioUnitEQ(numberOfBands: 1)
        e1.bands[0].bypass = true; e2.bands[0].bypass = true
        engine.attach(e1); engine.attach(e2)
        engine.connect(player, to: e1, format: fmt); engine.connect(e1, to: e2, format: fmt)
        engine.connect(e2, to: engine.mainMixerNode, format: fmt)
    } else {
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
    }
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 512)
    try! engine.start()
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 48000)!
    buf.frameLength = 48000
    for i in 0..<48000 { buf.floatChannelData![0][i] = 0.5; buf.floatChannelData![1][i] = 0.5 } // DC 0.5
    player.volume = changeMidway ? 1.0 : volume
    player.scheduleBuffer(buf, at: nil)
    player.play()
    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
    var y = [Float]()
    for b in 0..<40 {
        if changeMidway && b == 20 { player.volume = volume }
        _ = try! engine.renderOffline(512, to: out)
        y.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: 512))
    }
    return y
}
let direct = run(throughEffects: false, volume: 0.1, changeMidway: false)
let viaFx = run(throughEffects: true, volume: 0.1, changeMidway: false)
print("player.volume=0.1, DC in 0.5: direct-to-mixer out=\(direct[8000]), via 2 effect nodes out=\(viaFx[8000])")
let step = run(throughEffects: true, volume: 0.1, changeMidway: true)
let k0 = 20 * 512
print("volume 1.0 -> 0.1 at frame \(k0) (via effects): samples k0-2..k0+6 = \((k0-2...k0+6).map { String(format: "%.4f", step[$0]) }), k0+300=\(step[k0+300]), k0+600=\(step[k0+600])")
