// SoundAnalysis probe: list the built-in classifier's labels and time a whole-file analysis.
import AVFoundation
import Foundation
import SoundAnalysis

final class Collector: NSObject, SNResultsObserving {
    var windows = 0
    var tally: [String: Double] = [:]
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        windows += 1
        for c in r.classifications.prefix(5) { tally[c.identifier, default: 0] += c.confidence }
    }
    func request(_ request: SNRequest, didFailWithError error: Error) { print("fail: \(error)") }
    func requestDidComplete(_ request: SNRequest) {}
}

let args = CommandLine.arguments
let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
let labels = req.knownClassifications
print("known classifications: \(labels.count)")
let musicWords = ["music", "rock", "pop", "jazz", "hip", "classical", "country", "electronic", "reggae",
                  "blues", "folk", "metal", "disco", "funk", "soul", "techno", "house", "punk", "gospel",
                  "opera", "orchestra", "singing", "choir", "rapping", "guitar", "piano", "drum", "bass"]
let hits = labels.filter { l in musicWords.contains { l.lowercased().contains($0) } }
print("music-related labels (\(hits.count)): \(hits.sorted().joined(separator: ", "))")
print("window duration default: \(req.windowDuration.seconds) s, overlap: \(req.overlapFactor)")

if args.count > 1 {
    let url = URL(fileURLWithPath: args[1])
    let collector = Collector()
    let t0 = Date()
    let analyzer = try SNAudioFileAnalyzer(url: url)
    try analyzer.add(req, withObserver: collector)
    analyzer.analyze()
    let dt = Date().timeIntervalSince(t0)
    let dur = try AVAudioFile(forReading: url).length
    print(String(format: "analyzed %@ (%d frames) in %.2f s, %d windows", url.lastPathComponent, dur, dt, collector.windows))
    let top = collector.tally.sorted { $0.value > $1.value }.prefix(10)
    for (k, v) in top { print(String(format: "  %@ %.1f", k, v / Double(max(collector.windows, 1)))) }
}
