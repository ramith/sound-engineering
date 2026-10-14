// Passband + cost of AVAudioConverter at .max: the production algorithm (Normal) vs Mastering vs
// MinimumPhase, 44.1 -> 48 kHz, driven with the production chunking (8192 input frames per convert()).
// Amplitude is a least-squares fit of the steady-state output to sin/cos at f (no FFT scalloping).
import AVFoundation
import Foundation
let srcRate = Double(CommandLine.arguments[1])!

func run(algorithm: String, freq: Double, seconds: Double = 2) -> (gainDb: Double, residualDb: Double, rtf: Double) {
    let inFmt = AVAudioFormat(standardFormatWithSampleRate: srcRate, channels: 2)!
    let outFmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    let conv = AVAudioConverter(from: inFmt, to: outFmt)!
    conv.sampleRateConverterAlgorithm = algorithm
    conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    let total = Int(srcRate * seconds)
    var pos = 0
    var out: [Float] = []
    var cpu = 0.0
    var ended = false
    while !ended {
        let n = min(8192, total - pos)
        let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 8192)!
        inBuf.frameLength = AVAudioFrameCount(max(n, 0))
        for c in 0 ..< 2 { for i in 0 ..< max(n, 0) { inBuf.floatChannelData![c][i] = Float(0.5 * sin(2 * .pi * freq * Double(pos + i) / srcRate)) } }
        pos += max(n, 0)
        let reachedEnd = n <= 0
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 8192 * 2 + 4096)!
        var consumed = false
        var err: NSError?
        let t0 = DispatchTime.now().uptimeNanoseconds
        let st = conv.convert(to: outBuf, error: &err) { _, s in
            if consumed || inBuf.frameLength == 0 { s.pointee = reachedEnd ? .endOfStream : .noDataNow; return nil }
            consumed = true; s.pointee = .haveData; return inBuf
        }
        cpu += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
        out.append(contentsOf: UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
        if st == .endOfStream || reachedEnd { ended = true }
    }
    // LS fit on the steady state (skip 4096 at each end)
    var sxx = 0.0, sxy = 0.0, syy = 0.0, sxs = 0.0, sxc = 0.0, scc = 0.0, sss = 0.0, ssc = 0.0
    let lo = 4096, hi = out.count - 4096
    for j in lo ..< hi {
        let t = Double(j) / 48000, s = sin(2 * .pi * freq * t), c = cos(2 * .pi * freq * t), y = Double(out[j])
        sxs += y * s; sxc += y * c; sss += s * s; scc += c * c; ssc += s * c; syy += y * y
    }
    _ = (sxx, sxy)
    let det = sss * scc - ssc * ssc
    let a = (sxs * scc - sxc * ssc) / det, b = (sxc * sss - sxs * ssc) / det
    let amp = (a * a + b * b).squareRoot()
    var res = 0.0
    for j in lo ..< hi { let t = Double(j) / 48000; let e = Double(out[j]) - a * sin(2 * .pi * freq * t) - b * cos(2 * .pi * freq * t); res += e * e }
    let rms = (res / Double(hi - lo)).squareRoot()
    return (20 * log10(amp / 0.5), 20 * log10(rms / (0.5 / 2.0.squareRoot()) + 1e-30), cpu / seconds)
}

let algos = [("Normal (production)", AVSampleRateConverterAlgorithm_Normal), ("Mastering", AVSampleRateConverterAlgorithm_Mastering),
             ("MinimumPhase", AVSampleRateConverterAlgorithm_MinimumPhase)]
for (name, alg) in algos {
    var line = "\(name.padding(toLength: 20, withPad: " ", startingAt: 0)) gain dB @"
    var rtf = 0.0
    for f in [1000.0, 18000, 19000, 20000, 21000, 22000, 23000] {
        let r = run(algorithm: alg, freq: f)
        line += String(format: " %.0fk:%+.2f", f / 1000, r.gainDb)
        rtf = max(rtf, r.rtf)
    }
    let r1 = run(algorithm: alg, freq: 1000, seconds: 30)
    print(line + String(format: "  | 1 kHz residual %.0f dB; CPU %.2f ms per s of stereo audio (8192-frame chunks)", r1.residualDb, r1.rtf * 1000))
}
