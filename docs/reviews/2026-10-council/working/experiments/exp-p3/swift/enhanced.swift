// P3 breaker harness: the Enhanced path's seams, offline (AVAudioEngine manual rendering; no device).
// Each experiment mirrors the production code it names (file:line in the report).
import AVFoundation
import Foundation

let dataDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."
let graphRate = 48000.0
let block: AVAudioFrameCount = 512

func writeFile(_ name: String, rate: Double, channels: AVAudioChannelCount, frames: Int,
               _ gen: (Int, Int) -> Float) -> URL {
    let url = URL(fileURLWithPath: "\(dataDir)/\(name)")
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                   AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 32,
                                   AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false]
    let file = try! AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
    buf.frameLength = AVAudioFrameCount(frames)
    for c in 0 ..< Int(channels) { for i in 0 ..< frames { buf.floatChannelData![c][i] = gen(i, c) } }
    try! file.write(from: buf)
    return url
}

final class OfflineGraph {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let format: AVAudioFormat
    var out: [[Float]]
    init(channels: AVAudioChannelCount = 2, insertEffect: Bool = false) {
        format = AVAudioFormat(standardFormatWithSampleRate: graphRate, channels: channels)!
        out = Array(repeating: [], count: Int(channels))
        engine.attach(player)
        if insertEffect {
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            engine.attach(eq)
            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        try! engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: block)
        try! engine.start()
    }
    /// Render one block; paced = sleep the block's duration (emulates the real-time IO cycle so the
    /// completion callbacks run at a realistic point relative to the audio).
    func render(paced: Bool) {
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: block)!
        _ = try! engine.renderOffline(block, to: buf)
        for c in 0 ..< out.count { out[c].append(contentsOf: UnsafeBufferPointer(start: buf.floatChannelData![c], count: Int(buf.frameLength))) }
        if paced { usleep(useconds_t(Double(block) / graphRate * 1e6)) }
    }
    var rendered: Int { out[0].count }
    var playerSampleTime: Int64? {
        guard let nt = player.lastRenderTime, nt.isSampleTimeValid || nt.isHostTimeValid,
              let pt = player.playerTime(forNodeTime: nt) else { return nil }
        return pt.sampleTime
    }
}

// ---------------------------------------------------------------------------------------------
// A1: 48 kHz passthrough "gapless" seam: B is scheduled only when A's .dataPlayedBack fires
// (AudioEngineBridge+Playback.swift:210-223 -> +GaplessRoll.swift:72-89, :193-216).
func a1(paced: Bool, scheduleAhead: Bool, cb: AVAudioPlayerNodeCompletionCallbackType = .dataPlayedBack) {
    let a = writeFile("a1A.wav", rate: 48000, channels: 2, frames: 48000) { _, _ in 0.5 }
    let b = writeFile("a1B.wav", rate: 48000, channels: 2, frames: 48000) { _, _ in -0.5 }
    let g = OfflineGraph()
    let q = DispatchQueue(label: "resampleQueue")
    let fa = try! AVAudioFile(forReading: a), fb = try! AVAudioFile(forReading: b)
    var seamAtRendered = -1
    g.player.scheduleSegment(fa, startingFrame: 0, frameCount: AVAudioFrameCount(fa.length), at: nil,
                             completionCallbackType: cb) { _ in
        q.async {
            if !scheduleAhead {
                seamAtRendered = g.rendered
                g.player.scheduleFile(fb, at: nil, completionCallbackType: .dataPlayedBack) { _ in }
            }
        }
    }
    if scheduleAhead { g.player.scheduleFile(fb, at: nil, completionCallbackType: .dataPlayedBack) { _ in } }
    g.player.play()
    for _ in 0 ..< 200 { g.render(paced: paced); q.sync {} }
    let l = g.out[0]
    let lastA = l.lastIndex(where: { $0 > 0.25 }) ?? -1
    let firstB = l.firstIndex(where: { $0 < -0.25 }) ?? -1
    let cbName = cb == .dataPlayedBack ? "dataPlayedBack" : cb == .dataRendered ? "dataRendered" : "dataConsumed"
    print(String(format: "A1 [completion=%@] passthrough seam (%@, %@): A last sample @%d, B first @%d -> gap %d frames (%.1f ms)%@",
                 cbName, paced ? "paced" : "free-run", scheduleAhead ? "B scheduled behind A up front" : "B scheduled in A's completion",
                 lastA, firstB, firstB - lastA - 1, Double(firstB - lastA - 1) / 48.0,
                 seamAtRendered >= 0 ? " (completion ran when \(seamAtRendered) frames had rendered)" : ""))
}

// ---------------------------------------------------------------------------------------------
// A2: the resampler seam (EnhancedResampler*.swift + GaplessRoll.swift:34-64, :224-264): chain of
// 8192-frame converted chunks, prime 3, .dataConsumed chaining; EOF hook rolls to B and re-bases the
// position at the hook (Gapless.swift:184-205). Where does A's last sample actually render?
final class Session {
    let conv: AVAudioConverter; let file: AVAudioFile; let inFmt: AVAudioFormat; let outFmt: AVAudioFormat
    var reachedEnd = false; var consumed = false
    init(file: AVAudioFile, outFmt: AVAudioFormat) {
        self.file = file; inFmt = file.processingFormat; self.outFmt = outFmt
        conv = AVAudioConverter(from: inFmt, to: outFmt)!
        conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    }
    /// The production read -> convert step (EnhancedResamplerSeam.swift:81-163), verbatim logic.
    func nextChunk() -> AVAudioPCMBuffer? {
        let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 8192)!
        do { try file.read(into: inBuf, frameCount: 8192) } catch { reachedEnd = true }
        if inBuf.frameLength == 0 { reachedEnd = true }
        let ratio = outFmt.sampleRate / inFmt.sampleRate
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount((8192 * ratio).rounded(.up)) + 4096)!
        consumed = false
        var err: NSError?
        let st = conv.convert(to: outBuf, error: &err) { _, status in
            if self.consumed || inBuf.frameLength == 0 { status.pointee = self.reachedEnd ? .endOfStream : .noDataNow; return nil }
            self.consumed = true; status.pointee = .haveData; return inBuf
        }
        if st == .endOfStream { reachedEnd = true }
        if st == .error { reachedEnd = true; return nil }
        return outBuf
    }
}

func a2(paced: Bool, aFrames: Int) {
    let a = writeFile("a2A.wav", rate: 44100, channels: 2, frames: aFrames) { _, _ in 0.5 }
    let b = writeFile("a2B.wav", rate: 44100, channels: 2, frames: 44100 * 2) { _, _ in -0.5 }
    let g = OfflineGraph()
    let q = DispatchQueue(label: "resampleQueue")
    var gen = 0
    var session: Session!
    var hookRendered = -1
    var hookSampleTime: Int64 = -1
    var onEOF: (() -> Void)?
    var scheduledA = 0
    func step(_ s: Session, _ myGen: Int) -> Bool {
        guard myGen == gen, s === session else { return false }
        if s.reachedEnd { onEOF?(); onEOF = nil; return false }
        guard let out = s.nextChunk(), myGen == gen, out.frameLength > 0 else { return false }
        if s.file.url.lastPathComponent == "a2A.wav" { scheduledA += Int(out.frameLength) }
        g.player.scheduleBuffer(out, completionCallbackType: .dataConsumed) { _ in q.async { _ = step(s, myGen) } }
        return true
    }
    func prime(_ file: AVAudioFile) {
        session = Session(file: file, outFmt: g.player.outputFormat(forBus: 0))
        gen += 1
        let s = session!, my = gen
        for _ in 0 ..< 3 { if !step(s, my) { break } }
    }
    onEOF = {
        // rollResamplerToNext -> primeEnhancedResamplerLocked + bumpTransitionCount (the re-base point)
        prime(try! AVAudioFile(forReading: b))
        hookRendered = g.rendered
        hookSampleTime = g.playerSampleTime ?? -1
    }
    q.sync { prime(try! AVAudioFile(forReading: a)) }
    g.player.play()
    for _ in 0 ..< 600 { g.render(paced: paced); q.sync {} }
    let l = g.out[0]
    // A's audio ends where the output crosses from +0.5 to -0.5 (the seam).
    let firstB = l.firstIndex(where: { $0 < -0.25 }) ?? -1
    let early = firstB - hookRendered
    print(String(format: "A2 resampler seam (%@, A = %d frames @44.1k -> %d @48k): EOF hook ran at render frame %d "
                 + "(player sampleTime %lld); A's audio actually ends at frame %d -> re-base + B's loudness gain land %d frames "
                 + "= %.0f ms EARLY (+ the device's output latency on hardware)",
                 paced ? "paced" : "free-run", aFrames, scheduledA, hookRendered, hookSampleTime, firstB, early, Double(early) / 48.0))
}

// ---------------------------------------------------------------------------------------------
// A3: independent converter per track at a resampler->resampler seam. Oracle: one continuous
// conversion of the joined signal (what a single streaming SRC — or AVAudioEngine's own SRC on a
// scheduleFile chain — produces).
func convertWhole(_ file: AVAudioFile, outFmt: AVAudioFormat) -> [Float] {
    let s = Session(file: file, outFmt: outFmt)
    var out: [Float] = []
    while !s.reachedEnd || out.isEmpty {
        guard let b = s.nextChunk() else { break }
        out.append(contentsOf: UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength)))
        if s.reachedEnd { break }
    }
    // one more flush call as production does (reachedEnd -> the flush chunk was produced above)
    return out
}

func a3(freq: Double, splitAt: Int, label: String) {
    let total = 44100 * 4
    let gen: (Int, Int) -> Float = { i, _ in Float(0.5 * sin(2 * Double.pi * freq * Double(i) / 44100)) }
    let whole = writeFile("a3W.wav", rate: 44100, channels: 1, frames: total, gen)
    let pa = writeFile("a3A.wav", rate: 44100, channels: 1, frames: splitAt, gen)
    let pb = writeFile("a3B.wav", rate: 44100, channels: 1, frames: total - splitAt) { i, c in gen(i + splitAt, c) }
    let outFmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let w = convertWhole(try! AVAudioFile(forReading: whole), outFmt: outFmt)
    let ya = convertWhole(try! AVAudioFile(forReading: pa), outFmt: outFmt)
    let yb = convertWhole(try! AVAudioFile(forReading: pb), outFmt: outFmt)
    // Analytic oracle: an ideal resampler outputs the continuous sine at each track's own timeline.
    let tB = Double(splitAt) / 44100
    func ideal(_ t: Double) -> Float { Float(0.5 * sin(2 * Double.pi * freq * t)) }
    var nearJ: Float = 0, farJ: Float = 0, nearW: Float = 0
    for j in 0 ..< ya.count {
        let e = abs(ya[j] - ideal(Double(j) / 48000))
        if ya.count - j <= 300 { nearJ = max(nearJ, e) } else if j > 2000, ya.count - j > 2000 { farJ = max(farJ, e) }
    }
    for j in 0 ..< yb.count {
        let e = abs(yb[j] - ideal(tB + Double(j) / 48000))
        if j < 300 { nearJ = max(nearJ, e) } else if j > 2000, yb.count - j > 2000 { farJ = max(farJ, e) }
    }
    let seamW = Int(tB * 48000)
    for j in max(0, seamW - 300) ..< min(w.count, seamW + 300) { nearW = max(nearW, abs(w[j] - ideal(Double(j) / 48000))) }
    print(String(format: "A3 %@: A' %d frames (ideal %.2f), B' %d; per-track SRC error vs the analytic continuous sine: "
                 + "within 300 frames of the seam %.4f (%.1f dB re peak), elsewhere %.1e (%.1f dB); ONE continuous conversion at the same spot %.1e (%.1f dB)",
                 label, ya.count, Double(splitAt) * 48000 / 44100, yb.count, nearJ, 20 * log10(Double(nearJ) / 0.5),
                 farJ, 20 * log10(Double(farJ) / 0.5), nearW, 20 * log10(Double(nearW) / 0.5)))
}

// ---------------------------------------------------------------------------------------------
// A4: a seam that changes the channel count. Passthrough schedules B straight onto the player
// (GaplessRoll.swift:81-86); the resampler builds a converter file-format -> player format
// (Gapless.swift:212-225). Neither reconfigures the graph (that happens only in playFile).
func a4(mode: String) {
    switch mode {
    case "mono-on-stereo", "stereo-on-mono", "six-on-stereo", "stereo-on-stereo":
        let (fileCh, graphCh): (AVAudioChannelCount, AVAudioChannelCount) =
            mode == "mono-on-stereo" ? (1, 2) : mode == "stereo-on-mono" ? (2, 1) : mode == "six-on-stereo" ? (6, 2) : (2, 2)
        let f = writeFile("a4_\(mode).wav", rate: 48000, channels: fileCh, frames: 4800) { _, c in Float(c + 1) * 0.1 }
        let g = OfflineGraph(channels: graphCh)
        let file = try! AVAudioFile(forReading: f)
        print("A4 \(mode): scheduleFile(\(fileCh)-ch 48 kHz) on a \(graphCh)-ch player ...")
        fflush(stdout)
        g.player.scheduleFile(file, at: nil)
        g.player.play()
        for _ in 0 ..< 4 { g.render(paced: false) }
        let peaks = g.out.map { $0.map { abs($0) }.max() ?? 0 }
        print("A4 \(mode): no exception; per-channel output peak over 2048 frames: \(peaks) (file channel k carries 0.1*k)")
    case "convert-6to2", "convert-1to2":
        let inCh: AVAudioChannelCount = mode == "convert-6to2" ? 6 : 1
        let f = writeFile("a4_\(mode).wav", rate: 44100, channels: inCh, frames: 44100) { _, c in Float(c + 1) * 0.1 }
        let file = try! AVAudioFile(forReading: f)
        let outFmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let s = Session(file: file, outFmt: outFmt)
        let b = s.nextChunk()!
        let vals = (0 ..< 2).map { c in (0 ..< Int(b.frameLength)).map { abs(b.floatChannelData![c][$0]) }.max() ?? 0 }
        print("A4 \(mode): AVAudioConverter(\(inCh)ch@44.1k -> 2ch@48k) mid values L/R = \(vals) (input channel k carries 0.1*k)")
    default: break
    }
}

// ---------------------------------------------------------------------------------------------
// A6: Master Gain = AVAudioPlayerNode.volume with the player feeding an effect, not the mixer
// (production graph player -> effects AU -> spatial AU -> mixer). Does it apply, and is a change ramped?
func a6() {
    let g = OfflineGraph(channels: 2, insertEffect: true)
    let tone = AVAudioPCMBuffer(pcmFormat: g.format, frameCapacity: 48000)!
    tone.frameLength = 48000
    for c in 0 ..< 2 { for i in 0 ..< 48000 { tone.floatChannelData![c][i] = 0.5 } }
    g.player.scheduleBuffer(tone, at: nil, options: .loops)
    g.player.play()
    g.player.volume = 1.0
    for _ in 0 ..< 4 { g.render(paced: false) }
    g.player.volume = MasterGainProbe.linear(-6)
    for _ in 0 ..< 4 { g.render(paced: false) }
    let l = g.out[0]
    let before = l[4 * 512 - 1], first = l[4 * 512], tenth = l[4 * 512 + 10], settled = l[8 * 512 - 1]
    print(String(format: "A6 player.volume through an effect: level %.4f -> after setting -6 dB: first sample %.4f, +10 %.4f, settled %.4f (expected %.4f)",
                 before, first, tenth, settled, 0.5 * MasterGainProbe.linear(-6)))
}

// ---------------------------------------------------------------------------------------------
// A5: seek(to: duration) on the resampler path. Mirrors AudioEngineBridge+PureMode.swift:215-231 (base
// set to the target first) and +EnhancedResampler.swift:184-209 (generations bumped, THEN the frame
// guard refuses, no player.stop(), no restart).
func a5() {
    let frames = 44100 * 3 + 777
    let a = writeFile("a5.wav", rate: 44100, channels: 2, frames: frames) { _, _ in 0.5 }
    let g = OfflineGraph()
    let q = DispatchQueue(label: "resampleQueue")
    var gen = 0
    var session: Session!
    var eofFired = false
    func step(_ s: Session, _ my: Int) -> Bool {
        guard my == gen, s === session else { return false }
        if s.reachedEnd { eofFired = true; return false }   // fireResamplerEOFOrEnd (sets ended)
        guard let out = s.nextChunk(), my == gen, out.frameLength > 0 else { return false }
        g.player.scheduleBuffer(out, completionCallbackType: .dataConsumed) { _ in q.async { _ = step(s, my) } }
        return true
    }
    let file = try! AVAudioFile(forReading: a)
    q.sync { session = Session(file: file, outFmt: g.player.outputFormat(forBus: 0)); gen += 1; let s = session!, m = gen; for _ in 0 ..< 3 { if !step(s, m) { break } } }
    g.player.play()
    for _ in 0 ..< 94 { g.render(paced: true); q.sync {} }   // ~1 s in
    let duration = Double(file.length) / file.processingFormat.sampleRate   // the VM's duration
    var base = 0.0
    // --- the seek, as production orders it ---
    base = max(duration, 0)                                          // setEnhancedPositionBaseSeconds first
    var refused = false
    q.sync {
        gen += 1                                                     // resampleGeneration &+= 1 (and passthrough)
        let frame = AVAudioFramePosition(duration * file.processingFormat.sampleRate)
        if !(frame >= 0 && frame < file.length) { refused = true; return }   // capturedSession = nil; return
    }
    for _ in 0 ..< 470 { g.render(paced: true); q.sync {} }  // 5 s more
    let st = Double(g.playerSampleTime ?? 0) / 48000
    let tail = g.out[0].suffix(48000 * 3)
    print(String(format: "A5 seek(to: duration=%.4f s) on the resampler path: refused=%@; 5 s later: EOF fired=%@, player.isPlaying=%@, "
                 + "last 3 s peak %.3f (silent), position shown = base + sampleTime/rate = %.2f s (duration %.2f s)",
                 duration, refused ? "yes" : "no", eofFired ? "yes" : "NO", g.player.isPlaying ? "yes" : "no",
                 tail.map { abs($0) }.max() ?? 0, base + st, duration))
}

enum MasterGainProbe { static func linear(_ db: Float) -> Float { min(pow(10, db / 20), 1) } }

switch CommandLine.arguments[1] {
case "a1":
    a1(paced: true, scheduleAhead: false)
    a1(paced: true, scheduleAhead: false, cb: .dataRendered); a1(paced: false, scheduleAhead: false, cb: .dataRendered)
    a1(paced: true, scheduleAhead: false, cb: .dataConsumed)
    a1(paced: true, scheduleAhead: true)
case "a2":
    for frames in [44100 * 3 + 1234, 44100 * 3 + 8000, 8192 * 16] { a2(paced: true, aFrames: frames) }
    a2(paced: false, aFrames: 44100 * 3 + 1234)
case "a3":
    a3(freq: 1000, splitAt: 88200 + 17, label: "1 kHz sine, split mid-cycle")
    a3(freq: 50, splitAt: 88200 + 200, label: "50 Hz sine")
    a3(freq: 10000, splitAt: 88200 + 3, label: "10 kHz sine")
case "a4": a4(mode: CommandLine.arguments[3])
case "a6": a6()
case "a5": a5()
default: print("unknown")
}
