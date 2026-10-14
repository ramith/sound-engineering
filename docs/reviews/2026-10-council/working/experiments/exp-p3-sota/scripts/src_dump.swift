// AVAudioConverter in the PRODUCTION streaming pattern (8192-frame chunks, .noDataNow between chunks,
// .endOfStream at the end) — converts a raw mono float32 file. args: srcRate dstRate algo(normal|mastering|minphase) quality(max|high|...) in out
import AVFAudio
import Foundation
let a = CommandLine.arguments
let src = Double(a[1])!, dst = Double(a[2])!
let algo = ["normal": AVSampleRateConverterAlgorithm_Normal, "mastering": AVSampleRateConverterAlgorithm_Mastering,
            "minphase": AVSampleRateConverterAlgorithm_MinimumPhase][a[3]]!
let quality: AVAudioQuality = ["max": .max, "high": .high, "medium": .medium][a[4]]!
let data = try! Data(contentsOf: URL(fileURLWithPath: a[5]))
let x: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
let inFmt = AVAudioFormat(standardFormatWithSampleRate: src, channels: 1)!
let outFmt = AVAudioFormat(standardFormatWithSampleRate: dst, channels: 1)!
let c = AVAudioConverter(from: inFmt, to: outFmt)!
c.sampleRateConverterQuality = quality.rawValue
c.sampleRateConverterAlgorithm = algo
var pos = 0, out = [Float](), ended = false
out.reserveCapacity(Int(Double(x.count) * dst / src) + 10000)
let t0 = DispatchTime.now().uptimeNanoseconds
let chunk = 8192
while !ended {
    let n = min(chunk, x.count - pos)
    let inb = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(chunk))!
    inb.frameLength = AVAudioFrameCount(max(n, 0))
    if n > 0 { x.withUnsafeBufferPointer { inb.floatChannelData![0].update(from: $0.baseAddress! + pos, count: n) } }
    pos += max(n, 0)
    let reachedEnd = n <= 0
    let cap = AVAudioFrameCount((Double(chunk) * dst / src).rounded(.up)) + 4096
    let ob = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap)!
    var consumed = false
    let st = c.convert(to: ob, error: nil) { _, s in
        if consumed || inb.frameLength == 0 { s.pointee = reachedEnd ? .endOfStream : .noDataNow; return nil }
        consumed = true; s.pointee = .haveData; return inb
    }
    out.append(contentsOf: UnsafeBufferPointer(start: ob.floatChannelData![0], count: Int(ob.frameLength)))
    if st == .endOfStream || st == .error { ended = true }
}
let t1 = DispatchTime.now().uptimeNanoseconds
let secs = Double(t1 - t0) / 1e9
FileHandle.standardError.write("cpu_seconds=\(secs) audio_seconds=\(Double(x.count) / src) primeLeading=\(c.primeInfo.leadingFrames) primeTrailing=\(c.primeInfo.trailingFrames)\n".data(using: .utf8)!)
out.withUnsafeBufferPointer { try! Data(buffer: $0).write(to: URL(fileURLWithPath: a[6])) }
