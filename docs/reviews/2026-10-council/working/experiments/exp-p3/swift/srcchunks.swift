import AVFoundation
for (name, alg) in [("Normal", AVSampleRateConverterAlgorithm_Normal), ("Mastering", AVSampleRateConverterAlgorithm_Mastering)] {
  for src in [44100.0, 96000.0] {
    let inFmt = AVAudioFormat(standardFormatWithSampleRate: src, channels: 2)!
    let outFmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    let conv = AVAudioConverter(from: inFmt, to: outFmt)!
    conv.sampleRateConverterAlgorithm = alg
    conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    var counts: [Int] = []
    var total = 0
    let chunks = 12
    for k in 0 ... chunks {
        let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 8192)!
        inBuf.frameLength = k < chunks ? 8192 : 0
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 8192 * 2 + 4096)!
        var consumed = false; var err: NSError?
        let reachedEnd = k == chunks
        _ = conv.convert(to: outBuf, error: &err) { _, s in
            if consumed || inBuf.frameLength == 0 { s.pointee = reachedEnd ? .endOfStream : .noDataNow; return nil }
            consumed = true; s.pointee = .haveData; return inBuf }
        counts.append(Int(outBuf.frameLength)); total += Int(outBuf.frameLength)
    }
    print("\(name) \(Int(src))->48000 per-chunk output frames: \(counts) total \(total) (ideal \(Double(8192 * chunks) * 48000 / src))")
  }
}
