import AVFoundation
for p in CommandLine.arguments.dropFirst() {
  do { let f = try AVAudioFile(forReading: URL(fileURLWithPath: p))
       let lay = f.processingFormat.channelLayout
       let tag = lay?.layoutTag ?? 0xFFFF_FFFF
       let fileTag = f.fileFormat.channelLayout?.layoutTag ?? 0xFFFF_FFFF
       print(String(format: "%-14@ ch=%d procTag=0x%08X (low16=%d) fileTag=0x%08X", p as NSString, f.processingFormat.channelCount, tag, tag & 0xFFFF, fileTag))
  } catch { print(p, "error", error) }
}
