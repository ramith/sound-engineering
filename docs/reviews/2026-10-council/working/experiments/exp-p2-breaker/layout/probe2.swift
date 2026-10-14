import AVFoundation
import Accelerate
let freqs: [Double] = [200, 300, 400, 500, 600]
func dominant(_ p: UnsafePointer<Float>, _ n: Int, _ fs: Double) -> String {
    // Goertzel energy at each candidate frequency
    var best = (f: 0.0, e: 0.0); var tot = 0.0
    for f in freqs {
        let w = 2 * Double.pi * f / fs; let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for i in 0..<n { let s = Double(p[i]) + c * s1 - s2; s2 = s1; s1 = s }
        let e = s1 * s1 + s2 * s2 - c * s1 * s2
        tot += e; if e > best.e { best = (f, e) }
    }
    if tot < 1e-6 { return "silent" }
    return String(format: "%.0fHz(%.0f%%)", best.f, 100 * best.e / tot)
}
for name in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: name)
    let file = try! AVAudioFile(forReading: url)
    let pf = file.processingFormat
    let tag = pf.channelLayout?.layoutTag ?? 0
    var desc = "nil"
    if let l = pf.channelLayout { desc = String(format: "0x%08X", l.layoutTag) }
    // graph format = what MultichannelFormat.swift builds for 6 channels
    let graph = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    try! engine.enableManualRenderingMode(.offline, format: graph, maximumFrameCount: 4096)
    engine.connect(player, to: engine.mainMixerNode, format: graph)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: graph)
    try! engine.start()
    player.scheduleFile(file, at: nil)
    player.play()
    let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var acc = [[Float]](repeating: [], count: 6)
    for _ in 0..<6 {
        _ = try! engine.renderOffline(4096, to: buf)
        for c in 0..<Int(buf.format.channelCount) { acc[c] += Array(UnsafeBufferPointer(start: buf.floatChannelData![c], count: Int(buf.frameLength))) }
    }
    var out = "\(name): fileTag=\(desc) fileCh=\(pf.channelCount) -> graph(MPEG_5_1_A) out:"
    for c in 0..<2 { let a = acc[c]; out += " [\(c)]" + a.withUnsafeBufferPointer { dominant($0.baseAddress!.advanced(by: 4096), a.count - 4096, 48000) } }
    print(out)
    _ = tag
    engine.stop()
}
