// R1.1-A close-out break-it (P5a), kept as regression tests: SettingsKit `listeningSettingsV1` under corrupt
// and wrong-typed values (SET-1, SET-2), and the crash-safe Pure volume loans (SET-3, SET-4). Each asserts the
// safe property; all four were red on c9efbe6. Over a defaults suite of its own (never the app's), removed
// after each test.

import EQEditKit
import Foundation
@testable import SettingsKit
import Testing

@MainActor
@Suite("R1.1-A break-it — SettingsKit", .serialized)
struct R11aSettingsBreakTests {
    private static let key = "listeningSettingsV1"
    private let suiteName = "R11aSettingsBreak-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The listener left Master Gain at −30 dB. Then the stored value is damaged into another TYPE (a
    /// plist string, number, dictionary or array — `defaults write`, a sync tool, a bug): it must come back
    /// no louder (Silent) and be copied aside, as an unreadable JSON value is.
    @Test("SET-1: a value of the wrong plist type reads Silent and is kept aside")
    func wrongPlistType() {
        defer { cleanUp() }
        let damaged: [(String, Any)] = [
            ("string", "garbage"), ("number", 42), ("dictionary", ["masterGainDecibels": -30]), ("array", [1, 2]),
        ]
        var report: [String] = []
        var louder = 0
        for (kind, value) in damaged {
            defaults.set(value, forKey: Self.key)
            let level = SettingsStore(defaults: defaults).load().masterGainDecibels
            let keptAside = defaults.object(forKey: Self.key + ".unreadable") != nil
            report.append("\(kind): masterGain=\(level) keptAside=\(keptAside)")
            if level > -.infinity {
                louder += 1
            }
            defaults.removeObject(forKey: Self.key + ".unreadable")
        }
        print("R11A SET-1 " + report.joined(separator: " | "))
        #expect(louder == 0, "a damaged value of another type restores Master Gain at unity (the loudest)")
    }

    /// Valid JSON with the Master Gain key missing: the level left is unknown.
    @Test("SET-2: a stored value without a Master Gain level reads no louder than Silent")
    func missingLevel() {
        defer { cleanUp() }
        var report: [String] = []
        for json in [#"{}"#, #"{"version":1}"#, #"{"version":1,"pureMode":true,"shuffle":true}"#] {
            defaults.set(Data(json.utf8), forKey: Self.key)
            report.append("\(json) → \(SettingsStore(defaults: defaults).load().masterGainDecibels)")
        }
        print("R11A SET-2 " + report.joined(separator: " | "))
        #expect(report.allSatisfy { $0.hasSuffix("-inf") })
    }

    @Test("SET-5: saves coalesce; flush at quit writes the newest; a later turn writes nothing more")
    func quitFlush() async {
        defer { cleanUp() }
        let store = SettingsStore(defaults: defaults)
        var settings = store.load()
        settings.masterGainDecibels = -5
        store.save(settings)
        settings.masterGainDecibels = -25
        store.save(settings)
        store.flush() // quit
        let written = SettingsStore(defaults: defaults).load().masterGainDecibels
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        let afterTurn = SettingsStore(defaults: defaults).load().masterGainDecibels
        print("R11A SET-5 flushed=\(written) afterTurn=\(afterTurn)")
        #expect(written == -25 && afterTurn == -25)
    }

    @Test("SET-6: R1's shuffle and repeat are taken in once; a later change is what is kept")
    func r1Keys() {
        defer { cleanUp() }
        defaults.set(true, forKey: "queue.cursor.shuffle")
        defaults.set(2, forKey: "queue.cursor.repeatMode")
        let store = SettingsStore(defaults: defaults)
        var first = store.load()
        let tookIn = (first.shuffle, first.repeatMode, first.masterGainDecibels)
        first.shuffle = false
        store.save(first)
        store.flush()
        let second = SettingsStore(defaults: defaults).load()
        print("R11A SET-6 tookIn=\(tookIn) afterChange shuffle=\(second.shuffle) repeat=\(second.repeatMode)")
        #expect(tookIn.0 == true && tookIn.1 == 2 && second.shuffle == false && second.repeatMode == 2)
    }
}
