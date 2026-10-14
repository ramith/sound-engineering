import AVFoundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let f = try! AVAudioFile(forReading: url)
print("file fmt:", f.processingFormat, "layout:", f.processingFormat.channelLayout?.layoutTag ?? 0)
let outFmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
let c = AVAudioConverter(from: f.processingFormat, to: outFmt)!
c.sampleRateConverterQuality = AVAudioQuality.max.rawValue
print("channelMap:", c.channelMap, "downmix:", c.downmix)
let inBuf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 8192)!
try! f.read(into: inBuf, frameCount: 8192)
let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 12000)!
var done = false
var err: NSError?
let st = c.convert(to: out, error: &err) { _, s in if done { s.pointee = .noDataNow; return nil }; done = true; s.pointee = .haveData; return inBuf }
let peaks = (0..<2).map { ch in (0..<Int(out.frameLength)).map { abs(out.floatChannelData![ch][$0]) }.max() ?? 0 }
print("status:", st.rawValue, "err:", err as Any, "frames:", out.frameLength, "peaks:", peaks)
