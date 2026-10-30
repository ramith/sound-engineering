@testable import AdaptiveSound
@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit
import RigKit
import Testing

// MARK: - Break-it, R1.1-B sound half + the R1.1 close-out: a FLAC Apple's decoder refuses never kills the app

//
// KI-PB-22. A legal FLAC whose blocks are under 192 samples (ffmpeg makes them from Blu-ray audio; the corpus's
// `26-voice_5.1_48k_flac-tiny-blocks.flac`) opens in `AVAudioFile`, but every read throws, and the getter AND the
// setter of `AVAudioFile.framePosition` raise an uncaught NSException — the process dies (SIGABRT). Lane 1-B took
// the analyzer off it; the player still asks the file its position: the resampler's start
// (`+EnhancedResampler.swift:58`), its reader (`+EnhancedResamplerSeam.swift:169`) and the passthrough seam
// (`+GaplessRoll.swift:272`, `:281`).
//
// Each case runs in a CHILD process — this test bundle again, with only `BreakItCrashChild` selected (the
// `QueueStateKillTests` pattern) — through the REAL bridge on an offline engine (nothing is heard), so a crash
// fails one test here instead of ending the whole run. The parent reads how the child ended: a clean exit, or the
// signal that killed it.

/// What the parent tells its child, and how it runs one.
enum BreakItCrashHarness {
    static let caseKey = "AS_BIS_CRASH_CASE"

    /// The case this process runs as a child (nil: not a child).
    static var selected: String? {
        ProcessInfo.processInfo.environment[caseKey]
    }

    /// How a child ended.
    struct Ending: CustomStringConvertible {
        let reason: Process.TerminationReason
        let status: Int32
        let tail: String

        var survived: Bool {
            reason == .exit && status == 0
        }

        /// What the child said that matters: the exception, and the app's frames it was thrown through.
        var description: String {
            let keys = tail.split(separator: "\n").filter {
                $0.contains("Terminating app") || $0.contains("AVAudioFile") || $0.contains("AudioEngineBridge")
                    || $0.contains("Test run with")
            }
            return (reason == .uncaughtSignal ? "killed by signal \(status)" : "exit \(status)") + "\n"
                + keys.map { String($0.prefix(220)) }.joined(separator: "\n")
        }
    }

    /// Run case `name` in a child and wait for it to end (it is killed at the parent's time limit).
    static func run(_ name: String) async throws -> Ending {
        let arguments = CommandLine.arguments
        let flag = try #require(arguments.firstIndex(of: "--test-bundle-path"), "no --test-bundle-path to re-run")
        try #require(flag + 1 < arguments.count)
        let bundle = arguments[flag + 1]
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("breakit-crash-\(name)-\(UUID().uuidString).out")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = ["--test-bundle-path", bundle, bundle, "--testing-library", "swift-testing",
                             "--filter", "BreakItCrashChild"]
        var environment = ProcessInfo.processInfo.environment
        environment[caseKey] = name
        process.environment = environment
        let sink = try FileHandle(forWritingTo: output)
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        try await until("the child running '\(name)' to end") { !process.isRunning }
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        return Ending(reason: process.terminationReason, status: process.terminationStatus,
                      tail: String(text.suffix(20000)))
    }
}

@Suite("Break-it, sound: a tiny-block FLAC never kills the app (KI-PB-22)", .timeLimit(.minutes(5)), .serialized)
struct BreakItTinyBlockCrashTests {
    @Test("BI-S01: Play on a 44.1 kHz tiny-block FLAC (the resampler's start sets framePosition) — no crash")
    func startResampled() async throws {
        let ending = try await BreakItCrashHarness.run("start-44k")
        #expect(ending.survived, "playing a tiny-block FLAC killed the app process: \(ending)")
    }

    @Test("BI-S02: a gapless seam from a 48 kHz song into a 48 kHz tiny-block FLAC — no crash")
    func seamPassthrough() async throws {
        let ending = try await BreakItCrashHarness.run("seam-48k")
        #expect(ending.survived, "the seam into a tiny-block FLAC killed the app process: \(ending)")
    }

    @Test("BI-S03: a gapless seam from a 44.1 kHz song into a 44.1 kHz tiny-block FLAC — no crash")
    func seamResampled() async throws {
        let ending = try await BreakItCrashHarness.run("seam-44k")
        #expect(ending.survived, "the seam into a tiny-block FLAC killed the app process: \(ending)")
    }

    @Test("BI-S04 (control): the harness's child survives a clean 44.1 kHz song played to its end")
    func controlSurvives() async throws {
        let ending = try await BreakItCrashHarness.run("control")
        #expect(ending.survived, "the control child did not exit cleanly: \(ending)")
        #expect(ending.tail.contains("Test run with 1 test"), "the child ran its one test: \(ending)")
    }
}

/// The child: one case through the real bridge, then a clean exit. Enabled only in a process the parent spawned.
@Suite("Break-it, sound: the crash harness's child (BI-S01…S04 spawn it)", .timeLimit(.minutes(3)),
       .enabled(if: BreakItCrashHarness.selected != nil))
struct BreakItCrashChild {
    @Test("the child: play the case through the real bridge, render, end")
    func child() async throws {
        switch BreakItCrashHarness.selected {
        case "start-44k":
            let rig = try await MultichannelDeviceRig.make(deviceChannels: 2)
            let url = try BreakItTinyFlac.write(named: "start-44k", rate: 44100, blockSize: 128)
            defer { try? FileManager.default.removeItem(at: url) }
            try? await rig.play(url)
            _ = try? await rig.render(frames: 48000)
            await rig.finish()
        case "seam-48k", "seam-44k", "control":
            let resampled = BreakItCrashHarness.selected != "seam-48k"
            let rig = try await EnhancedTransportRig(path: resampled ? .resampler : .passthrough, name: "bis-seam",
                                                     frames: 4800)
            let next = try BreakItTinyFlac.write(named: "seam", rate: resampled ? 44100 : 48000,
                                                 blockSize: BreakItCrashHarness.selected == "control" ? 4096 : 128)
            defer { try? FileManager.default.removeItem(at: next) }
            await rig.bridge.setNextTrack(next, ticket: OnDeckTicket(session: 0, sequence: 1), leveling: .off)
            _ = try await rig.samples(seconds: 1.5)
            await rig.finish()
        default:
            Issue.record("unknown case \(BreakItCrashHarness.selected ?? "nil")")
        }
    }
}

/// A minimal FLAC (RFC 9639) at 44.1 or 48 kHz: 16-bit mono, one second of a 440 Hz tone at −12 dBFS, VERBATIM
/// subframes in blocks of `blockSize` samples. Apple's decoder refuses blocks under 192 samples; 4096 is the
/// control. Written to test-data/breakit-sound/ (ignored by git), generated at test time.
enum BreakItTinyFlac {
    static func write(named name: String, rate: Int, blockSize: Int, seconds: Double = 1) throws -> URL {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-data/breakit-sound", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name)-\(blockSize)-\(UUID().uuidString).flac")
        let count = Int(seconds * Double(rate))
        let samples = (0 ..< count).map { Int16(8000 * sin(2 * Double.pi * 440 * Double($0) / Double(rate))) }
        let rateCode: UInt8 = rate == 44100 ? 0x9 : 0xA // 1001 = 44.1 kHz, 1010 = 48 kHz
        let sizeCode: UInt8 = blockSize <= 256 ? 0x6 : 0x7 // 0110: 8-bit (size − 1) at the end; 0111: 16-bit
        var out = [UInt8]("fLaC".utf8)
        var info = bigEndian(UInt64(blockSize), bytes: 2) + bigEndian(UInt64(blockSize), bytes: 2)
        info += [UInt8](repeating: 0, count: 6)
        info += bigEndian((UInt64(rate) << 44) | (15 << 36) | UInt64(count), bytes: 8)
        info += [UInt8](repeating: 0, count: 16)
        out += [0x80] + bigEndian(UInt64(info.count), bytes: 3) + info
        for (number, start) in stride(from: 0, to: count, by: blockSize).enumerated() {
            let block = samples[start ..< min(start + blockSize, count)]
            var frame: [UInt8] = [0xFF, 0xF8, (sizeCode << 4) | rateCode, 0x08] + utf8(number)
            frame += sizeCode == 0x6 ? [UInt8(block.count - 1)] : bigEndian(UInt64(block.count - 1), bytes: 2)
            frame.append(crc8(frame))
            frame.append(0x02) // a VERBATIM subframe
            for sample in block {
                frame += bigEndian(UInt64(UInt16(bitPattern: sample)), bytes: 2)
            }
            frame += bigEndian(UInt64(crc16(frame)), bytes: 2)
            out += frame
        }
        try Data(out).write(to: url)
        return url
    }

    private static func bigEndian(_ value: UInt64, bytes: Int) -> [UInt8] {
        (0 ..< bytes).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    private static func utf8(_ number: Int) -> [UInt8] {
        switch number {
        case ..<0x80: [UInt8(number)]
        case ..<0x800: [UInt8(0xC0 | (number >> 6)), UInt8(0x80 | (number & 0x3F))]
        default: [UInt8(0xE0 | (number >> 12)), UInt8(0x80 | ((number >> 6) & 0x3F)), UInt8(0x80 | (number & 0x3F))]
        }
    }

    private static func crc8(_ data: [UInt8]) -> UInt8 {
        data.reduce(into: UInt8(0)) { crc, byte in
            crc ^= byte
            for _ in 0 ..< 8 {
                crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1
            }
        }
    }

    private static func crc16(_ data: [UInt8]) -> UInt16 {
        data.reduce(into: UInt16(0)) { crc, byte in
            crc ^= UInt16(byte) << 8
            for _ in 0 ..< 8 {
                crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x8005 : crc << 1
            }
        }
    }
}
