import AVFoundation
for p in CommandLine.arguments.dropFirst() {
    do { let f = try AVAudioFile(forReading: URL(fileURLWithPath: p)); print(p, "OK", f.processingFormat.sampleRate, f.length) }
    catch { print(p, "FAIL", error.localizedDescription) }
}
