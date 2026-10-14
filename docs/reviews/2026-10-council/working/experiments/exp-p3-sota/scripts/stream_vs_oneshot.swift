// Is the production chunked pull pattern (8192 + .noDataNow) bit-identical to a one-shot conversion
// (SRCQualityMeasure's pattern)? If yes, the D38 tool's numbers transfer to production.
import AVFAudio
import Foundation
let inFmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
let outFmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
var seed: UInt64 = 7
let x: [Float] = (0..<200_000).map { _ in seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: seed >> 11) % 10000) / 20000 }
func run(chunk: Int) -> [Float] {
    let c = AVAudioConverter(from: inFmt, to: outFmt)!; c.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    var pos = 0, out = [Float](), ended = false
    while !ended {
        let n = min(chunk, x.count - pos)
        let inb = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(chunk))!
        inb.frameLength = AVAudioFrameCount(max(n, 0))
        for i in 0..<max(n, 0) { inb.floatChannelData![0][i] = x[pos + i] }
        pos += max(n, 0); let reached = n <= 0
        let ob = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(Double(chunk) * 48000 / 44100) + 8192)!
        var consumed = false
        let st = c.convert(to: ob, error: nil) { _, s in
            if consumed || inb.frameLength == 0 { s.pointee = reached ? .endOfStream : .noDataNow; return nil }
            consumed = true; s.pointee = .haveData; return inb
        }
        out.append(contentsOf: UnsafeBufferPointer(start: ob.floatChannelData![0], count: Int(ob.frameLength)))
        if st == .endOfStream || st == .error { ended = true }
    }
    return out
}
let one = run(chunk: 200_000), ch = run(chunk: 8192), odd = run(chunk: 1031)
var d1: Float = 0, d2: Float = 0
for i in 0..<min(one.count, ch.count) { d1 = max(d1, abs(one[i] - ch[i])) }
for i in 0..<min(one.count, odd.count) { d2 = max(d2, abs(one[i] - odd[i])) }
print("lengths one-shot=\(one.count) chunk8192=\(ch.count) chunk1031=\(odd.count); max|diff| 8192=\(d1) 1031=\(d2); expected length=\(Double(x.count) * 48000 / 44100)")
