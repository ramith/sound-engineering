import AVFoundation
// per-tone level in each output channel (dB re input tone amplitude 0.2)
let url = URL(fileURLWithPath: CommandLine.arguments[1]); let file = try! AVAudioFile(forReading: url)
let graph = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
let engine = AVAudioEngine(); let player = AVAudioPlayerNode(); engine.attach(player)
try! engine.enableManualRenderingMode(.offline, format: graph, maximumFrameCount: 4096)
engine.connect(player, to: engine.mainMixerNode, format: graph); engine.connect(engine.mainMixerNode, to: engine.outputNode, format: graph)
try! engine.start(); player.scheduleFile(file, at: nil); player.play()
let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
var acc = [[Float]](repeating: [], count: 2)
for _ in 0..<8 { _ = try! engine.renderOffline(4096, to: buf); for c in 0..<2 { acc[c] += Array(UnsafeBufferPointer(start: buf.floatChannelData![c], count: Int(buf.frameLength))) } }
for c in 0..<2 { var s = "out[\(c)]:"; for f in [200.0,300,400,500,600] { var re = 0.0, im = 0.0; let a = acc[c]; let n = a.count - 8192
  for i in 8192..<a.count { let w = 2*Double.pi*f*Double(i)/48000; re += Double(a[i])*cos(w); im += Double(a[i])*sin(w) }
  let amp = 2*sqrt(re*re+im*im)/Double(n); s += String(format: " %3.0fHz:%6.1fdB", f, 20*log10(max(amp,1e-9)/0.2)) }; print(s) }
