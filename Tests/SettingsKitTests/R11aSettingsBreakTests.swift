// R1.1-A close-out break-it (P5a), kept as regression tests: SettingsKit `listeningSettingsV1` under corrupt
// and wrong-typed values (SET-1, SET-2), and the crash-safe Pure volume loans (SET-3, SET-4). Each asserts the
// safe property; all four were red on b1cc33c. Over a defaults suite of its own (never the app's), removed
// after each test.

import EQEditKit
import Foundation
import RigKit
@testable import SettingsKit
import Testing

@MainActor
@Suite("R1.1-A break-it — SettingsKit", .timeLimit(.minutes(3)))
struct R11aSettingsBreakTests {
    private static let key = "listeningSettingsV1"
    /// The suite of this test's own, removed with it.
    private let world = IsolatedDefaults("R11aSettingsBreak")
    private var defaults: UserDefaults {
        world.defaults
    }

    /// The listener left Master Gain at −30 dB. Then the stored value is damaged into another TYPE (a
    /// plist string, number, dictionary or array — `defaults write`, a sync tool, a bug): it must come back
    /// no louder (Silent) and be copied aside, as an unreadable JSON value is.
    @Test("SET-1: a value of the wrong plist type reads Silent and is kept aside")
    func wrongPlistType() {
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
        var report: [String] = []
        for json in [#"{}"#, #"{"version":1}"#, #"{"version":1,"pureMode":true,"shuffle":true}"#] {
            defaults.set(Data(json.utf8), forKey: Self.key)
            report.append("\(json) → \(SettingsStore(defaults: defaults).load().masterGainDecibels)")
        }
        print("R11A SET-2 " + report.joined(separator: " | "))
        #expect(report.allSatisfy { $0.hasSuffix("-inf") })
    }

    /// One malformed loan must not cost the others: each one is a device left turned down. (The loans moved
    /// from `listeningSettingsV1` to their own journal — H-2 — which reads them one by one.)
    @Test("SET-3: one bad Pure volume loan doesn't drop the good ones")
    func oneBadLoan() {
        let json = #"[{"deviceUID":"DAC-A","ceiling":-20,"anchor":-20,"lastSet":-32},"#
            + #"{"deviceUID":"DAC-B","ceiling":"oops","anchor":-20,"lastSet":-32}]"#
        defaults.set(Data(json.utf8), forKey: "pureVolumeLoansV1")
        let loans = PureVolumeLoanJournal(defaults: defaults).loans()
        print("R11A SET-3 loans read: \(loans.map(\.deviceUID))")
        #expect(loans.map(\.deviceUID) == ["DAC-A"])
    }

    /// A kept loan is put back at launch. The rule says Pure "never sets it higher [than the ceiling], nor
    /// puts back more" — but a damaged loan (anchor above its ceiling, or NaN) is put back as stored.
    @Test("SET-4: a damaged kept loan never puts a device back above its ceiling, nor NaN")
    func damagedLoanReturn() {
        final class Device: DeviceVolumeControl {
            var level: Float
            var sets: [Float] = []
            init(level: Float) {
                self.level = level
            }

            func read() -> DeviceVolumeReading? {
                DeviceVolumeReading(level: level, range: -64 ... 0)
            }

            func set(_ decibels: Float) -> Bool {
                sets.append(decibels)
                level = decibels
                return true
            }
        }
        var report: [String] = []
        var bad = 0
        for (name, anchor) in [("anchor above ceiling", Float(0)), ("NaN anchor", Float.nan)] {
            let loan = PureVolumeLoan(deviceUID: "DAC", ceiling: -30, anchor: anchor, lastSet: -40)
            var pure = MasterGainOnPure(unreturned: [loan])
            let device = Device(level: -40) // still reads what Pure last set: the loan is returned
            pure.returnUnreturned { _ in device }
            report.append("\(name): device set to \(device.sets)")
            if device.sets.contains(where: { !($0 <= -30) }) {
                bad += 1
            }
        }
        print("R11A SET-4 " + report.joined(separator: " | "))
        #expect(bad == 0)
    }

    @Test("SET-5: saves coalesce; flush at quit writes the newest; a later turn writes nothing more")
    func quitFlush() async {
        let store = SettingsStore(defaults: defaults)
        var settings = store.load()
        settings.masterGainDecibels = -5
        store.save(settings)
        settings.masterGainDecibels = -25
        store.save(settings)
        store.flush() // quit
        let written = SettingsStore(defaults: defaults).load().masterGainDecibels
        await store.pendingWrite?.value
        let afterTurn = SettingsStore(defaults: defaults).load().masterGainDecibels
        print("R11A SET-5 flushed=\(written) afterTurn=\(afterTurn)")
        #expect(written == -25 && afterTurn == -25)
    }

    @Test("SET-6: R1's shuffle and repeat are taken in once; a later change is what is kept")
    func r1Keys() {
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
