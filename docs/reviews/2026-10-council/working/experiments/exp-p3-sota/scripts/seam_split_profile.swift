// Exp C: per-track AVAudioConverter (.max, Normal prime) split vs one continuous conversion — no
// player, no timing: pure DSP. Prints the join error profile and its energy. Also .mastering.
import AVFAudio
import Foundation
let srcRate = 44100.0, outRate = 48000.0
let inFmt = AVAudioFormat(standardFormatWithSampleRate: srcRate, channels: 1)!
let outFmt = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: 1)!
func conv(_ x: [Float], algo: String?) -> [Float] {
    let c = AVAudioConverter(from: inFmt, to: outFmt)!
    c.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    if let a = algo { c.sampleRateConverterAlgorithm = a }
    var pos = 0, out = [Float](), ended = false
    while !ended {
        let n = min(8192, x.count - pos)
        let inb = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 8192)!
        inb.frameLength = AVAudioFrameCount(max(n, 0))
        for i in 0..<max(n, 0) { inb.floatChannelData![0][i] = x[pos + i] }
        pos += max(n, 0)
        let reached = n <= 0
        let ob = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 8192 * 2 + 4096)!
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
let mode = CommandLine.arguments[1]  // "sine" or "noise"
let total = 44100 * 3, split = Int(CommandLine.arguments[2])!
var x = [Float](repeating: 0, count: total)
var seed: UInt64 = 1
for i in 0..<total {
    if mode == "noise" { seed = seed &* 6364136223846793005 &+ 1442695040888963407; x[i] = Float(Int64(bitPattern: seed >> 11) % 1000) / 4000.0 }
    else { x[i] = Float(0.45 * sin(2 * .pi * 60 * Double(i) / srcRate) + 0.2 * sin(2 * .pi * 3000 * Double(i) / srcRate)) }
}
for algo in [nil, AVSampleRateConverterAlgorithm_Mastering] {
    let whole = conv(x, algo: algo)
    let a = conv(Array(x[0..<split]), algo: algo), b = conv(Array(x[split...]), algo: algo)
    let joined = a + b
    let seamOut = a.count
    var e = [Float](); for k in 0..<min(whole.count, joined.count) { e.append(joined[k] - whole[k]) }
    var maxe: Float = 0, idx = 0; for k in 0..<e.count where abs(e[k]) > maxe { maxe = abs(e[k]); idx = k }
    var energy: Double = 0, sig: Double = 0
    for k in (seamOut - 2000)..<(seamOut + 2000) { energy += Double(e[k] * e[k]); sig += Double(whole[k] * whole[k]) }
    // width of the region with |e| > 1e-4
    var lo = seamOut, hi = seamOut
    for k in stride(from: seamOut, to: seamOut - 3000, by: -1) where abs(e[k]) > 1e-4 { lo = k }
    for k in seamOut..<(seamOut + 3000) where abs(e[k]) > 1e-4 { hi = k }
    print("\(mode) algo=\(algo ?? "normal"): lengths whole=\(whole.count) a+b=\(joined.count) (Δ \(joined.count - whole.count)); " +
          "max|e|=\(maxe) at seam\(idx - seamOut >= 0 ? "+" : "")\(idx - seamOut); |e|>1e-4 spans [\(lo - seamOut), +\(hi - seamOut)] frames; " +
          "join error energy / signal energy in ±2000 = \(String(format: "%.1f", 10 * log10(energy / sig))) dB")
}
