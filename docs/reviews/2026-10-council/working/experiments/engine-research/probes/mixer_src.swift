// Offline probe: SRC quality of AVAudioEngine's own sample-rate conversion, i.e. the path SFBAudioEngine
// uses (source node at the FILE rate -> mainMixer -> output at the DEVICE rate), versus an inserted
// AUConverter node set to Mastering complexity. Manual rendering (offline) only: no device is opened,
// nothing is played.
//
// Build: swiftc -O mixer_src.swift -o mixer_src
// Usage: ./mixer_src
import AVFoundation
import AudioToolbox
import Foundation

enum Path: String { case mixer = "mixer(default)", converterMastering = "AUConverter(Mastering,max)", converterNormal = "AUConverter(Normal,max)" }

final class ToneState: @unchecked Sendable {
    var phase: [Double]
    var freqs: [Double]
    let amp: Double
    let rate: Double
    var noise = false
    var rng: UInt64 = 0x1234_5678_9abc_def1
    init(freqs: [Double], amp: Double, rate: Double) {
        self.freqs = freqs; self.amp = amp; self.rate = rate; self.phase = Array(repeating: 0, count: freqs.count)
    }
    func next() -> Float {
        if noise {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(Int64(bitPattern: rng >> 11) & ((1 << 52) - 1)) / Double(1 << 52) - 0.5) * 0.5
        }
        var s = 0.0
        for i in 0..<freqs.count {
            s += sin(phase[i])
            phase[i] += 2 * Double.pi * freqs[i] / rate
            if phase[i] > 2 * Double.pi { phase[i] -= 2 * Double.pi }
        }
        return Float(amp * s)
    }
}

/// Renders `frames` output frames at `outRate` from a source at `inRate`.
func render(path: Path, inRate: Double, outRate: Double, state: ToneState, frames: Int, channels: AVAudioChannelCount = 2) throws -> [Float] {
    let engine = AVAudioEngine()
    let outFmt = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: channels)!
    try engine.enableManualRenderingMode(.offline, format: outFmt, maximumFrameCount: 4096)
    let inFmt = AVAudioFormat(standardFormatWithSampleRate: inRate, channels: channels)!
    let src = AVAudioSourceNode(format: inFmt) { _, _, frameCount, abl -> OSStatus in
        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        for f in 0..<Int(frameCount) {
            let v = state.next()
            for b in bufs { b.mData!.assumingMemoryBound(to: Float.self)[f] = v }
        }
        return noErr
    }
    engine.attach(src)
    switch path {
    case .mixer:
        engine.connect(src, to: engine.mainMixerNode, format: inFmt)
    case .converterMastering, .converterNormal:
        let desc = AudioComponentDescription(componentType: kAudioUnitType_FormatConverter,
                                             componentSubType: kAudioUnitSubType_AUConverter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        let sem = DispatchSemaphore(value: 0)
        var unit: AVAudioUnit?
        var instErr: Error?
        AVAudioUnit.instantiate(with: desc, options: []) { u, e in unit = u; instErr = e; sem.signal() }
        sem.wait()
        guard let conv = unit else { throw instErr ?? NSError(domain: "probe", code: 1) }
        var complexity: UInt32 = path == .converterMastering ? kAudioUnitSampleRateConverterComplexity_Mastering
                                                             : kAudioUnitSampleRateConverterComplexity_Normal
        var st = AudioUnitSetProperty(conv.audioUnit, kAudioUnitProperty_SampleRateConverterComplexity,
                                      kAudioUnitScope_Global, 0, &complexity, UInt32(MemoryLayout<UInt32>.size))
        if st != noErr { print("  [warn] set complexity status \(st)") }
        var quality: UInt32 = UInt32(kRenderQuality_Max)
        st = AudioUnitSetProperty(conv.audioUnit, kAudioUnitProperty_RenderQuality, kAudioUnitScope_Global, 0,
                                  &quality, UInt32(MemoryLayout<UInt32>.size))
        if st != noErr { print("  [warn] set render quality status \(st)") }
        engine.attach(conv)
        engine.connect(src, to: conv, format: inFmt)
        engine.connect(conv, to: engine.mainMixerNode, format: outFmt)
    }
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outFmt)
    try engine.start()
    let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var out = [Float](); out.reserveCapacity(frames)
    while out.count < frames {
        let n = min(4096, frames - out.count)
        let st = try engine.renderOffline(AVAudioFrameCount(n), to: buf)
        guard st == .success else { throw NSError(domain: "probe", code: Int(st.rawValue)) }
        let p = buf.floatChannelData![0]
        out.append(contentsOf: UnsafeBufferPointer(start: p, count: Int(buf.frameLength)))
    }
    engine.stop()
    return out
}

/// Least-squares amplitude of a sinusoid at `f` (no window, no scalloping).
func lsAmp(_ x: ArraySlice<Float>, f: Double, rate: Double) -> Double {
    var ss = 0.0, cc = 0.0, sc = 0.0, xs = 0.0, xc = 0.0
    var i = 0.0
    for v in x {
        let w = 2 * Double.pi * f * i / rate
        let s = sin(w), c = cos(w)
        ss += s * s; cc += c * c; sc += s * c; xs += Double(v) * s; xc += Double(v) * c
        i += 1
    }
    let det = ss * cc - sc * sc
    let a = (xs * cc - xc * sc) / det
    let b = (xc * ss - xs * sc) / det
    return (a * a + b * b).squareRoot()
}

func db(_ v: Double) -> String { String(format: "%7.2f", 20 * log10(max(v, 1e-12))) }

let skip = 16384, len = 65536
let paths: [Path] = [.mixer, .converterMastering, .converterNormal]

print("== Passband: tone amplitude 0.5, gain in dB re input (LS fit) ==")
for (inR, outR) in [(44100.0, 48000.0), (96000.0, 48000.0), (192000.0, 48000.0), (48000.0, 44100.0)] {
    for p in paths {
        var line = String(format: "%6.0f->%6.0f %-28@", inR, outR, p.rawValue as NSString)
        for f in [1000.0, 10000.0, 18000.0, 19000.0, 20000.0, 21000.0] {
            if f >= min(inR, outR) / 2 { continue }
            do {
                let st = ToneState(freqs: [f], amp: 0.5, rate: inR)
                let y = try render(path: p, inRate: inR, outRate: outR, state: st, frames: skip + len)
                line += " \(Int(f / 1000))k:" + db(lsAmp(y[skip...], f: f, rate: outR) / 0.5)
            } catch { line += " ERR(\(error))" }
        }
        print(line)
    }
}

print("\n== Stopband: out-of-band tone (amp 0.5) folded to its alias; alias level dB re tone ==")
for inR in [96000.0, 192000.0, 88200.0] {
    let outR = 48000.0
    for p in paths {
        var line = String(format: "%6.0f->%6.0f %-28@", inR, outR, p.rawValue as NSString)
        for f in [24500.0, 25000.0, 26000.0, 30000.0] {
            do {
                let st = ToneState(freqs: [f], amp: 0.5, rate: inR)
                let y = try render(path: p, inRate: inR, outRate: outR, state: st, frames: skip + len)
                let alias = outR - f   // first fold for outR/2 < f < outR
                line += " \(f/1000)k->\(alias/1000)k:" + db(lsAmp(y[skip...], f: alias, rate: outR) / 0.5)
            } catch { line += " ERR(\(error))" }
        }
        print(line)
    }
}

print("\n== Equal-rate transparency through mainMixer (noise, 48k->48k and 44.1k->44.1k) ==")
for r in [48000.0, 44100.0] {
    let st = ToneState(freqs: [], amp: 0, rate: r); st.noise = true
    let ref = ToneState(freqs: [], amp: 0, rate: r); ref.noise = true
    let y = try render(path: .mixer, inRate: r, outRate: r, state: st, frames: 1 << 17)
    var maxDiff: Float = 0
    for i in 0..<y.count { maxDiff = max(maxDiff, abs(y[i] - ref.next())) }
    print(String(format: "%6.0f: max |out - in| = %g (0 = bit-transparent)", r, maxDiff))
}
