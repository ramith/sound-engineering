// Exp B: faithful replica of the Enhanced resampler chain + gapless roll
// (+EnhancedResampler.swift / +EnhancedResamplerSeam.swift / +GaplessRoll.swift: 8192-frame chunks,
// .max quality, prime 3, .dataConsumed chaining, EOF = a 0-frame read then an endOfStream flush,
// roll = open next file + NEW converter + prime 3 on the serial queue).
// Offline manual rendering paced at real time. Measures (1) the silence inserted at the seam and
// (2) the waveform error around the join vs ONE converter run over the concatenated signal.
import AVFAudio
import Foundation

let srcRate = 44100.0, outRate = 48000.0
let inFmt = AVAudioFormat(standardFormatWithSampleRate: srcRate, channels: 2)!
let outFmt = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: 2)!
let dir = CommandLine.arguments[1]
let chunk: AVAudioFrameCount = 8192

func signal(_ n: Int) -> Float {  // continuous program across the split: 60 Hz + 3 kHz
    let t = Double(n) / srcRate
    return Float(0.45 * sin(2 * .pi * 60 * t) + 0.2 * sin(2 * .pi * 3000 * t))
}
func writeFile(_ name: String, start: Int, count: Int) -> URL {
    let url = URL(fileURLWithPath: dir + "/" + name)
    try? FileManager.default.removeItem(at: url)
    let f = try! AVAudioFile(forWriting: url, settings: inFmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let b = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(count))!
    b.frameLength = AVAudioFrameCount(count)
    for i in 0..<count { let v = signal(start + i); b.floatChannelData![0][i] = v; b.floatChannelData![1][i] = v }
    try! f.write(from: b)
    return url
}

final class Session: @unchecked Sendable {
    let converter: AVAudioConverter; let file: AVAudioFile
    var reachedEnd = false; var inputConsumed = false
    init(file: AVAudioFile) {
        converter = AVAudioConverter(from: file.processingFormat, to: outFmt)!
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        self.file = file
    }
}
func convertChunk(_ s: Session, _ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    let cap = AVAudioFrameCount((Double(chunk) * outRate / srcRate).rounded(.up)) + 4096
    let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap)!
    s.inputConsumed = false
    var err: NSError?
    let st = s.converter.convert(to: out, error: &err) { _, status in
        if s.inputConsumed || input.frameLength == 0 { status.pointee = s.reachedEnd ? .endOfStream : .noDataNow; return nil }
        s.inputConsumed = true; status.pointee = .haveData; return input
    }
    if st == .error { s.reachedEnd = true; return nil }
    if st == .endOfStream { s.reachedEnd = true }
    return out
}
func readChunk(_ s: Session) -> AVAudioPCMBuffer {
    let b = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: chunk)!
    do { try s.file.read(into: b, frameCount: chunk) } catch { s.reachedEnd = true }
    if b.frameLength == 0 { s.reachedEnd = true }
    return b
}

final class Chain: @unchecked Sendable {
    let q = DispatchQueue(label: "resampleQueue")
    let player: AVAudioPlayerNode
    var generation: UInt64 = 0
    var session: Session?
    var onDeck: URL?
    var tailFrames = 0, lastPartialOut = 0
    var seamAtRendered = -1
    var renderedRef: UnsafeMutablePointer<Int>
    var stalledChain = false
    init(player: AVAudioPlayerNode, rendered: UnsafeMutablePointer<Int>) { self.player = player; renderedRef = rendered }

    func readConvertSchedule(_ s: Session, _ gen: UInt64) -> Bool {
        guard gen == generation, session === s else { return false }
        if s.reachedEnd { fireEOF(); return false }
        let input = readChunk(s)
        guard let out = convertChunk(s, input) else { return false }
        guard gen == generation, session === s else { return false }
        guard out.frameLength > 0 else { stalledChain = true; return false }  // production: chain silently stops
        if s.reachedEnd { tailFrames = Int(out.frameLength) } else if input.frameLength < chunk { lastPartialOut = Int(out.frameLength) }
        player.scheduleBuffer(out, completionCallbackType: .dataConsumed) { [self] _ in
            q.async { _ = self.readConvertSchedule(s, gen) }
        }
        return true
    }
    func prime(_ s: Session) -> Int {
        generation &+= 1; let gen = generation; session = s
        var n = 0
        for _ in 0..<3 { if !readConvertSchedule(s, gen) { break }; n += 1 }
        return n
    }
    func fireEOF() {
        guard let next = onDeck else { return }
        onDeck = nil
        seamAtRendered = renderedRef.pointee
        let f = try! AVAudioFile(forReading: next)          // production: openNextFileOrRestart
        _ = prime(Session(file: f))                           // production: startResamplerChainOrFallback
    }
}

func runReplica(lenA: Int, lenB: Int) -> (y: [Float], chain: Chain) {
    let urlA = writeFile("rA.wav", start: 0, count: lenA)
    let urlB = writeFile("rB.wav", start: lenA, count: lenB)
    let engine = AVAudioEngine(); let player = AVAudioPlayerNode()
    engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: outFmt)
    try! engine.enableManualRenderingMode(.offline, format: outFmt, maximumFrameCount: 512)
    try! engine.start()
    let rendered = UnsafeMutablePointer<Int>.allocate(capacity: 1); rendered.pointee = 0
    let chain = Chain(player: player, rendered: rendered)
    chain.q.sync { chain.onDeck = urlB; _ = chain.prime(Session(file: try! AVAudioFile(forReading: urlA))) }
    player.play()
    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
    var y = [Float]()
    let total = Int(Double(lenA + lenB) * outRate / srcRate) + 24000
    while y.count < total {
        _ = try! engine.renderOffline(512, to: out)
        y.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        rendered.pointee = y.count
        Thread.sleep(forTimeInterval: 512.0 / outRate)
    }
    engine.stop()
    return (y, chain)
}

// Reference: ONE converter over the concatenated program, same streaming pattern, flushed at the end.
func reference(len: Int) -> [Float] {
    let url = writeFile("ref.wav", start: 0, count: len)
    let s = Session(file: try! AVAudioFile(forReading: url))
    var r = [Float]()
    while true {
        let input = readChunk(s)
        guard let out = convertChunk(s, input) else { break }
        r.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        if s.reachedEnd { break }
    }
    return r
}

for (label, lenA) in [("A ends 64 frames into its last chunk", 8192 * 8 + 64),
                      ("A ends 4096 frames into its last chunk", 8192 * 8 + 4096),
                      ("A ends 8100 frames into its last chunk", 8192 * 8 + 8100)] {
    let lenB = 8192 * 6
    let ref = reference(len: lenA + lenB)
    let (y, chain) = runReplica(lenA: lenA, lenB: lenB)
    let seamOut = Int((Double(lenA) * outRate / srcRate).rounded())
    // Find where B's region of the reference lands in y (search offset d >= -50 around the seam)
    var bestD = 0, bestErr = Float.infinity
    for d in -50..<24000 {
        var e: Float = 0
        for k in 2000..<2400 { e = max(e, abs(y[seamOut + d + k] - ref[seamOut + k])) }
        if e < bestErr { bestErr = e; bestD = d }
        if e < 1e-4 { break }
    }
    // Waveform error around the join (A's tail and B's head), aligned by bestD for B
    var errA: Float = 0, errB: Float = 0
    for k in (seamOut - 200)..<seamOut { errA = max(errA, abs(y[k] - ref[k])) }
    for k in 0..<200 { errB = max(errB, abs(y[seamOut + bestD + k] - ref[seamOut + k])) }
    var interior: Float = 0
    for k in 20000..<20400 { interior = max(interior, abs(y[k] - ref[k])) }
    print("\(label): gap inserted at seam = \(bestD) frames (\(String(format: "%.1f", Double(bestD) / 48)) ms); " +
          "A's last partial chunk = \(chain.lastPartialOut) out frames, flush tail = \(chain.tailFrames) frames; " +
          "chainStalled=\(chain.stalledChain); EOF hook fired at rendered frame \(chain.seamAtRendered), A ends at out frame \(seamOut) -> lead \(seamOut - chain.seamAtRendered) frames")
    print("   join error vs one continuous conversion: A tail max |e| = \(errA), B head max |e| = \(errB); interior max |e| = \(interior)")
}
