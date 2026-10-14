// Exp A: AVAudioPlayerNode seam gap — production pattern (schedule B from A's completion) vs
// pre-scheduled B. Offline manual rendering (no device), paced at real time so async completions
// take wall-clock time as on a device. In manual rendering .dataPlayedBack == .dataRendered (header),
// so a measured gap is a LOWER BOUND of the on-device gap (which adds output presentation latency).
import AVFAudio
import Foundation

let rate = 48000.0
let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
let dir = CommandLine.arguments[1]
let freq = 441.0
func writeFile(_ path: String, start: Int, count: Int) -> URL {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let f = try! AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(count))!
    b.frameLength = AVAudioFrameCount(count)
    for i in 0..<count {
        let v = Float(0.5 * sin(2 * Double.pi * freq * Double(start + i) / rate))
        b.floatChannelData![0][i] = v; b.floatChannelData![1][i] = v
    }
    try! f.write(from: b)
    return url
}
let lenA = 72000 + 37   // 1.5 s + odd frames
let lenB = 72000
let urlA = writeFile(dir + "/A.wav", start: 0, count: lenA)
let urlB = writeFile(dir + "/B.wav", start: lenA, count: lenB)

enum Pattern: String { case fromCompletion, preScheduled }
func run(_ pattern: Pattern, callback: AVAudioPlayerNodeCompletionCallbackType, paced: Bool) -> (gap: Int?, note: String) {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: fmt)
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 512)
    try! engine.start()
    let q = DispatchQueue(label: "resampleQueue-replica")
    let fileA = try! AVAudioFile(forReading: urlA)
    switch pattern {
    case .fromCompletion:
        // Production (AudioEngineBridge+Playback.swift:211-224 / +GaplessRoll.swift:207-215):
        // B is opened and scheduled only when A's completion fires.
        player.scheduleSegment(fileA, startingFrame: 0, frameCount: AVAudioFrameCount(lenA), at: nil,
                               completionCallbackType: callback) { _ in
            q.async {
                let fileB = try! AVAudioFile(forReading: urlB)
                player.scheduleFile(fileB, at: nil, completionCallbackType: callback) { _ in }
            }
        }
    case .preScheduled:
        player.scheduleSegment(fileA, startingFrame: 0, frameCount: AVAudioFrameCount(lenA), at: nil)
        let fileB = try! AVAudioFile(forReading: urlB)
        player.scheduleFile(fileB, at: nil)
    }
    player.play()
    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
    var y = [Float]()
    let total = lenA + lenB + 48000
    while y.count < total {
        _ = try! engine.renderOffline(512, to: out)
        y.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        if paced { Thread.sleep(forTimeInterval: 512.0 / rate) }
    }
    engine.stop()
    // A must be intact; then find where B's first 64 samples land (offset d from lenA).
    var aOK = true
    for i in 0..<lenA where abs(y[i] - Float(0.5 * sin(2 * Double.pi * freq * Double(i) / rate))) > 1e-5 { aOK = false; break }
    let bRef = (0..<64).map { Float(0.5 * sin(2 * Double.pi * freq * Double(lenA + $0) / rate)) }
    // B's head could also be TRUNCATED (played "following the last one" in the past): search B offsets too.
    for d in 0..<48000 {
        var ok = true
        for k in 0..<64 where abs(y[lenA + d + k] - bRef[k]) > 1e-5 { ok = false; break }
        if ok { return (d, "A intact=\(aOK), B head intact") }
    }
    for skip in 1..<24000 {   // B starts somewhere inside B (head dropped)?
        let ref2 = (0..<64).map { Float(0.5 * sin(2 * Double.pi * freq * Double(lenA + skip + $0) / rate)) }
        for d in 0..<4096 {
            var ok = true
            for k in 0..<64 where abs(y[lenA + d + k] - ref2[k]) > 1e-5 { ok = false; break }
            if ok { return (d, "A intact=\(aOK), B HEAD TRUNCATED by \(skip) frames (or phase-aliased match)") }
        }
    }
    return (nil, "A intact=\(aOK), B not found")
}
for (p, cb, paced) in [(Pattern.preScheduled, AVAudioPlayerNodeCompletionCallbackType.dataRendered, true), (.fromCompletion, .dataRendered, true), (.fromCompletion, .dataRendered, false),
                       (.fromCompletion, .dataPlayedBack, true),
                       (.fromCompletion, .dataConsumed, true),
                       (.fromCompletion, .dataPlayedBack, false)] {
    for trial in 0..<3 {
        let r = run(p, callback: cb, paced: paced)
        print("pattern=\(p.rawValue) cb=\(cb.rawValue) paced=\(paced) trial=\(trial): gap=\(r.gap.map { "\($0) frames (\(String(format: "%.1f", Double($0) / 48.0)) ms)" } ?? "n/a")  \(r.note)")
    }
}
