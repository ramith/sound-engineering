import Foundation
import Accelerate
import AudioToolbox
import AVFoundation
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "levels"
if mode == "levels" {
    // Drive the REAL analyzer with known sines and report the published (normalised) band values.
    for fs: Float in [44100, 48000, 96000, 192000] {
        let a = SpectrumAnalyzer(fftSize: 4096, sampleRate: fs)
        for (f0, amp) in [(1000.0, 1.0), (1000.0, 0.1), (997.0, 1.0), (100.0, 1.0), (45.0, 1.0)] as [(Double, Float)] {
            let n = 4096
            let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(fs), channels: 2)!
            let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
            buf.frameLength = AVAudioFrameCount(n)
            for i in 0..<n { let v = amp * Float(sin(2 * Double.pi * f0 * Double(i) / Double(fs))); buf.floatChannelData![0][i] = v; buf.floatChannelData![1][i] = v }
            var out = [Float](repeating: 0, count: 44)
            for _ in 0..<40 { a.processTapBuffer(buf.mutableAudioBufferList, frameCount: buf.frameLength, channelCount: 2) } // settle ballistics
            _ = a.doubleBuffer.read(into: &out)
            let k = out.indices.max { out[$0] < out[$1] }!
            let db = out[k] * 80 - 80
            print(String(format: "fs %6.0f  sine %6.1f Hz amp %.2f (%.1f dBFS) → peak band %2d (%.0f Hz) value %.4f = %+.2f dB", fs, f0, amp, 20*log10(amp), k, SpectrumConstants.bandCentreHz(Float(k)), out[k], db))
        }
        // short-buffer case: a 1024-frame tap of a full-scale 1 kHz sine
        let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(fs), channels: 2)!
        let b2 = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!; b2.frameLength = 1024
        for i in 0..<1024 { let v = Float(sin(2 * Double.pi * 1000 * Double(i) / Double(fs))); b2.floatChannelData![0][i] = v; b2.floatChannelData![1][i] = v }
        let a2 = SpectrumAnalyzer(fftSize: 4096, sampleRate: fs); var o2 = [Float](repeating: 0, count: 44)
        a2.processTapBuffer(b2.mutableAudioBufferList, frameCount: 1024, channelCount: 2); _ = a2.doubleBuffer.read(into: &o2)
        let k2 = o2.indices.max { o2[$0] < o2[$1] }!
        print(String(format: "   1024-frame tap, 0 dBFS 1 kHz → peak band %d value %.3f = %+.1f dB", k2, o2[k2], o2[k2]*80-80))
    }
    // low-band bin sharing at each rate
    for fs: Float in [44100, 48000, 192000] {
        let hz = fs / 4096
        var shared = 0; var dcBands = 0
        var prev = (-1, -1)
        for b in 0..<44 { let c = SpectrumConstants.bandCentreHz(Float(b)); let lo = Int(c / powf(2, 1/12) / hz); let hi = max(lo, Int(c * powf(2, 1/12) / hz)); if (lo, hi) == prev { shared += 1 }; if lo == 0 { dcBands += 1 }; prev = (lo, hi) }
        print(String(format: "fs %.0f: %d of 44 bands duplicate the previous band's bin range; %d include the DC bin", fs, shared, dcBands))
    }
} else {
    // race: hammer the double buffer from two threads
    let db = SpectrumDoubleBuffer(count: 44)
    let src = [Float](repeating: 1, count: 44)
    let t = Thread { var v = src; for i in 0..<20_000_000 { for j in 0..<44 { v[j] = Float(i % 1000) }; v.withUnsafeBufferPointer { db.write($0) } } }
    t.start()
    var out = [Float](repeating: 0, count: 44); var reads = 0
    let end = Date().addingTimeInterval(3)
    var torn = 0
    while Date() < end { if db.read(into: &out) { reads += 1; if out.contains(where: { $0 != out[0] }) { torn += 1 } } }
    print("reads \(reads) torn \(torn)")
}
