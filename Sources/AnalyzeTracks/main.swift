// AnalyzeTracks — the read-only analysis tool (R1.1-B, founder decision 4; the level-and-fold design,
// docs/design/level-and-fold/README.md, "The analysis tool" and §8½ C4).
//
// For every audio file named on the command line (folders are walked), it runs the one analysis pass exactly as
// the app will (TrackLoudnessKit's TrackAnalysisPass: AVAudioFile, the Mastering converter into F1's format at
// 48 kHz, the C++ analyzer) and prints what it measured: loudness and true peak as decoded and on the BS.775 fold
// at each LFE variant, the head and tail blocks, the LFE statistics with the LFE rule's verdict, and the cost.
// It READS ONLY: it writes nothing anywhere — no store, nothing in AppDataLocation — and plays nothing.
//
//   swift run AnalyzeTracks [--json] [--album] <file or folder>…
//     --json    one JSON object per file on stdout (for scripts), instead of the table
//     --album   also the album's anchors over all the files: the loudest track's L and the pooled L (§3, F-1)

import AudioDSP
import Foundation
import TrackLoudnessKit

struct Options {
    var json = false
    var album = false
    var paths: [String] = []
}

func parse(_ arguments: [String]) -> Options? {
    var options = Options()
    for argument in arguments {
        switch argument {
        case "--json":
            options.json = true
        case "--album":
            options.album = true
        case "-h", "--help":
            return nil
        default:
            if argument.hasPrefix("-") {
                return nil
            }
            options.paths.append(argument)
        }
    }
    return options.paths.isEmpty ? nil : options
}

/// Every regular file under `paths` (folders walked, sorted by path; hidden files skipped).
func files(under paths: [String]) -> [URL] {
    var found: [URL] = []
    for path in paths {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            FileHandle.standardError.write(Data("AnalyzeTracks: no such file: \(path)\n".utf8))
            continue
        }
        guard isFolder.boolValue else {
            found.append(url)
            continue
        }
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles])
        let inside = (walker?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        found += inside.sorted { $0.path < $1.path }
    }
    return found
}

/// The CPU seconds this process has used (user + system).
func processCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    return user + system
}

let roleNames = ["?", "L", "R", "C", "LFE", "Ls", "Rs", "Lb", "Rb", "Cs", "Lc", "Rc", "Lw", "Rw", "Mono"]
let variantNames = ["omit", "−6 dB", "0 dB", "+4 dB"]
let verdictNames = ["Omit (unknown)", "Omit (a copy)", "Include (redirected bass)", "Include (independent)",
                    "Omit (uncertain)"]

func number(_ value: Double?, _ digits: Int = 2) -> String {
    guard let value else { return "—" }
    return String(format: "%+.\(digits)f", value)
}

func share(_ value: Double?) -> String {
    value.map { String(format: "%.3f", $0) } ?? "—"
}

func verdict(of analysis: TrackAnalysis) -> String {
    var stats = analysis.lfe.stats
    let verdict = Int(asFoldDecideLfe(&stats))
    return verdict < verdictNames.count ? verdictNames[verdict] : "verdict \(verdict)"
}

func table(_ url: URL, _ analysis: TrackAnalysis, wall: Double, cpu: Double) -> String {
    let roles = analysis.roles.map { Int($0) < roleNames.count ? roleNames[Int($0)] : "#\($0)" }.joined(separator: " ")
    var lines = [url.path]
    lines.append("  format   \(analysis.channelCount) ch @ \(Int(analysis.sourceRateHz)) Hz → measured at "
        + "\(Int(analysis.peakRateHz)) Hz   roles \(roles)   \(String(format: "%.2f", analysis.durationSeconds)) s")
    lines.append("  decoded  L \(number(analysis.integratedLufs)) LUFS   TP \(number(analysis.truePeakDbtp)) dBTP   "
        + "head \(number(analysis.headBlockLufs, 1))   tail \(number(analysis.tailBlockLufs, 1)) LUFS")
    if analysis.folds {
        let folds = (0 ..< analysis.foldedLufs.count).map {
            "\(variantNames[$0]) \(number(analysis.foldedLufs[$0])) / \(number(analysis.foldedTruePeakDbtp[$0]))"
        }
        lines.append("  fold     L / TP by LFE variant:   " + folds.joined(separator: "   "))
    }
    let lfe = analysis.lfe
    if lfe.activeBlocks > 0 || lfe.medianR2 != nil {
        lines.append("  LFE      active \(lfe.activeBlocks)   lag \(number(lfe.lagMs, 0)) ms   peak "
            + "\(share(lfe.lagPeak))   coherent \(share(lfe.coherentShare))   median r² \(share(lfe.medianR2))"
            + "   p90 r² \(share(lfe.p90R2))   excess20 \(share(lfe.excess20Share))   explain "
            + "\(number(lfe.explainGainDb, 1)) dB   → \(verdict(of: analysis))")
    }
    let realTime = analysis.durationSeconds / max(wall, 1e-9)
    lines.append("  cost     \(String(format: "%.2f", wall)) s wall, \(String(format: "%.2f", cpu)) s CPU "
        + "(\(String(format: "%.1f", realTime))× real time)")
    return lines.joined(separator: "\n")
}

/// One JSON object on one line (keys sorted).
func jsonLine(_ object: [String: Any]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    return String(bytes: data, encoding: .utf8) ?? "{}"
}

func json(_ url: URL, _ analysis: TrackAnalysis, wall: Double, cpu: Double) -> String {
    let lfe = analysis.lfe
    let object: [String: Any] = [
        "file": url.path,
        "channels": analysis.channelCount,
        "sourceRateHz": analysis.sourceRateHz,
        "roles": analysis.roles.map { Int($0) < roleNames.count ? roleNames[Int($0)] : "#\($0)" },
        "seconds": analysis.durationSeconds,
        "integratedLufs": analysis.integratedLufs ?? NSNull(),
        "truePeakDbtp": analysis.truePeakDbtp ?? NSNull(),
        "headBlockLufs": analysis.headBlockLufs ?? NSNull(),
        "tailBlockLufs": analysis.tailBlockLufs ?? NSNull(),
        "folds": analysis.folds,
        "foldedLufs": analysis.foldedLufs.map { $0 ?? NSNull() as Any },
        "foldedTruePeakDbtp": analysis.foldedTruePeakDbtp.map { $0 ?? NSNull() as Any },
        "lfe": [
            "activeBlocks": lfe.activeBlocks, "lagMs": lfe.lagMs ?? NSNull(), "lagPeak": lfe.lagPeak ?? NSNull(),
            "coherentShare": lfe.coherentShare ?? NSNull(), "medianR2": lfe.medianR2 ?? NSNull(),
            "p90R2": lfe.p90R2 ?? NSNull(), "excess20Share": lfe.excess20Share ?? NSNull(),
            "explainGainDb": lfe.explainGainDb ?? NSNull(), "verdict": verdict(of: analysis),
        ] as [String: Any],
        "wallSeconds": wall,
        "cpuSeconds": cpu,
    ]
    return jsonLine(object)
}

guard let options = parse(Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data("usage: AnalyzeTracks [--json] [--album] <file or folder>…\n".utf8))
    exit(2)
}

var analysed: [TrackAnalysis] = []
var failures = 0
for url in files(under: options.paths) {
    guard let identity = TrackIdentity(url: url) else {
        failures += 1
        continue
    }
    let started = Date()
    let cpuBefore = processCPUSeconds()
    let outcome = TrackAnalysisPass.analyse(url, identity: identity)
    let wall = Date().timeIntervalSince(started)
    let cpu = processCPUSeconds() - cpuBefore
    switch outcome {
    case let .analysed(analysis, _):
        analysed.append(analysis)
        print(options.json ? json(url, analysis, wall: wall, cpu: cpu) : table(url, analysis, wall: wall, cpu: cpu))
    case let .failed(reason):
        failures += 1
        if options.json {
            let object = ["file": url.path, "failed": reason]
            print(jsonLine(object))
        } else {
            print("\(url.path)\n  not analysed: \(reason)")
        }
    case .cancelled:
        failures += 1
    }
}

if options.album, !analysed.isEmpty {
    let loudest = analysed.compactMap(\.integratedLufs).max()
    let pooled = TrackAnalysis.pooledLufs(analysed, basis: 0)
    let anchor = analysed.max { ($0.integratedLufs ?? -.infinity) < ($1.integratedLufs ?? -.infinity) }
    if options.json {
        let object: [String: Any] = [
            "album": analysed.count, "loudestTrackLufs": loudest ?? NSNull(),
            "loudestTrack": anchor?.identity.path ?? NSNull(), "pooledLufs": pooled ?? NSNull(),
        ]
        print(jsonLine(object))
    } else {
        print("album of \(analysed.count): loudest track \(number(loudest)) LUFS "
            + "(\(anchor.map { URL(fileURLWithPath: $0.identity.path).lastPathComponent } ?? "—")), "
            + "pooled \(number(pooled)) LUFS")
    }
}

exit(failures == 0 ? 0 : 1)
