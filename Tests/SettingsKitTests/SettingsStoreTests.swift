// SETTINGS — the listener's settings and their one store (R1.1-A, FD-2; council C-12, C-102, DEV-1):
// the faithful default, the round trip, a bad field read as its default, Master Gain never restored
// louder than it was left, R1's shuffle / repeat taken in once, and writes coalesced per main-actor turn.
// Over a defaults suite of its own, emptied before each test.

import EQEditKit
import Foundation
import RigKit
@testable import SettingsKit
import Testing

@MainActor
@Suite("SettingsStore — the listener's settings, kept", .timeLimit(.minutes(3)))
struct SettingsStoreTests {
    private static let key = "listeningSettingsV1"

    /// The suite of this test's own, removed with it.
    private let world = IsolatedDefaults("SettingsKitTests")
    private var defaults: UserDefaults {
        world.defaults
    }

    private func stored(_ json: String) {
        defaults.set(Data(json.utf8), forKey: Self.key)
    }

    private func load() -> ListeningSettings {
        SettingsStore(defaults: defaults).load()
    }


    /// Every setting away from its default.
    private static let changed = ListeningSettings(
        pureMode: true, masterGainDecibels: -17, crossfeed: true, crossfeedStrength: .relaxed, shuffle: true,
        repeatMode: 1, keepPlaybackOnDevice: false, chosenOutputUID: "AppleUSBAudioEngine:DAC:1", useFFmpeg: true
    )

    @Test("SETTINGS-01: a new install reads the faithful default, and reading writes nothing")
    func newInstallIsFaithful() {
        let settings = load()
        #expect(settings == ListeningSettings.faithful)
        #expect(!settings.pureMode && settings.masterGainDecibels == MasterGainLaw.unity && !settings.crossfeed)
        #expect(settings.crossfeedStrength == .defaultStrength && !settings.shuffle && settings.repeatMode == 0)
        #expect(settings.keepPlaybackOnDevice && settings.chosenOutputUID == nil)
        #expect(!settings.useFFmpeg, "FFmpeg is an opt-in (FD-3)")
        #expect(defaults.object(forKey: Self.key) == nil)
    }

    @Test("SETTINGS-02: what is saved is what the next launch reads — Silent included")
    func roundTrip() {
        let store = SettingsStore(defaults: defaults)
        _ = store.load()
        store.save(Self.changed)
        store.flush()
        #expect(load() == Self.changed)

        var silent = Self.changed
        silent.masterGainDecibels = -.infinity
        store.save(silent)
        store.flush()
        #expect(load().masterGainDecibels == -.infinity)
    }

    @Test("SETTINGS-03: one versioned value, its version inside, Silent written as text")
    func storedForm() throws {
        let store = SettingsStore(defaults: defaults)
        _ = store.load()
        var settings = Self.changed
        settings.masterGainDecibels = -.infinity
        store.save(settings)
        store.flush()
        let data = try #require(defaults.data(forKey: Self.key))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(object["masterGainDecibels"] as? String == "-Infinity")
        #expect(object["crossfeedStrength"] as? Int == CrossfeedStrength.relaxed.rawValue)
    }

    @Test("SETTINGS-04: saves coalesce — written at the end of the turn, once, the newest; equal ones not at all")
    func savesCoalesce() async {
        let store = SettingsStore(defaults: defaults)
        _ = store.load()
        var first = ListeningSettings.faithful
        first.shuffle = true
        store.save(first)
        store.save(Self.changed)
        #expect(defaults.object(forKey: Self.key) == nil, "nothing is written within the turn")
        await store.pendingWrite?.value
        #expect(load() == Self.changed, "the turn's newest settings, written once it ended")

        // The faithful default saved over a new install's: equal to what is stored, so never written.
        defaults.removePersistentDomain(forName: world.suiteName)
        let fresh = SettingsStore(defaults: defaults)
        fresh.save(fresh.load())
        await fresh.pendingWrite?.value
        #expect(defaults.object(forKey: Self.key) == nil)
    }

    @Test("SETTINGS-05: a bad field reads as its faithful default; the others still read")
    func badFieldsFallBack() {
        stored(#"{"version":1,"pureMode":true,"crossfeed":"on","crossfeedStrength":7,"shuffle":1,"#
            + #""repeatMode":3,"keepPlaybackOnDevice":false,"chosenOutputUID":""}"#)
        let settings = load()
        #expect(settings.pureMode, "a good field survives its bad neighbours")
        #expect(!settings.keepPlaybackOnDevice)
        #expect(!settings.crossfeed)
        #expect(settings.crossfeedStrength == .defaultStrength)
        #expect(!settings.shuffle)
        #expect(settings.repeatMode == 0)
        #expect(settings.chosenOutputUID == nil)
        #expect(settings.masterGainDecibels == -.infinity, "version 1 always writes it: absent is damage, Silent")

        // A later build's value: its new fields are ignored, the known ones read.
        stored(#"{"version":2,"shuffle":true,"leveling":"album","masterGainDecibels":-6}"#)
        #expect(load() == ListeningSettings(masterGainDecibels: -6, shuffle: true))
    }

    @Test("SETTINGS-09: FFmpeg is off on a new install and after an R1.1 value without it; a bad value reads off")
    func ffmpegIsAnOptIn() {
        // A value written before the setting existed: off.
        stored(#"{"version":1,"pureMode":true}"#)
        #expect(!load().useFFmpeg)
        stored(#"{"version":1,"useFFmpeg":"yes"}"#)
        #expect(!load().useFFmpeg, "a bad value is the faithful default: off")
        stored(#"{"version":1,"useFFmpeg":true}"#)
        #expect(load().useFFmpeg, "turned on, it stays on")
    }

    /// The never-louder rule against every kind of bad stored value (R1.1-A close-out break-it, SET-1 / SET-2):
    /// whatever can't be what the listener left reads Silent — a value of another plist type, JSON that
    /// isn't an object or doesn't parse, an object with no level, and a level that is not a number, ±∞ or
    /// above 0 dB. A damaged value of any kind is copied aside before anything overwrites it.
    @Test("SETTINGS-11: Master Gain is never restored louder, whatever is stored — every bad value reads Silent")
    func neverLouderForAnyBadValue() {
        let unreadable = Self.key + ".unreadable"
        let wrongTypes: [(String, Any)] = [
            ("a string", "garbage"), ("a number", 42), ("a bool", true), ("a date", Date()),
            ("a dictionary", ["masterGainDecibels": -30]), ("an array", [1, 2]),
        ]
        for (what, value) in wrongTypes {
            defaults.removePersistentDomain(forName: world.suiteName)
            defaults.set(value, forKey: Self.key)
            #expect(load().masterGainDecibels == -.infinity, "\(what): read louder than Silent")
            #expect(defaults.object(forKey: unreadable) != nil, "\(what): not kept aside")
        }
        let badJSON = ["not json at all", "[]", #""text""#, "5", "null", #"{"version":1"#]
        for json in badJSON {
            defaults.removePersistentDomain(forName: world.suiteName)
            stored(json)
            #expect(load().masterGainDecibels == -.infinity, "\(json): read louder than Silent")
            #expect(defaults.object(forKey: unreadable) != nil, "\(json): not kept aside")
        }
        let badLevels = [
            #"{}"#, #"{"version":1}"#, #"{"version":1,"pureMode":true}"#, #"{"masterGainDecibels":null}"#,
            #"{"masterGainDecibels":"NaN"}"#, #"{"masterGainDecibels":"+Infinity"}"#,
            #"{"masterGainDecibels":"-Infinity"}"#, #"{"masterGainDecibels":0.5}"#, #"{"masterGainDecibels":3}"#,
            #"{"masterGainDecibels":"loud"}"#, #"{"masterGainDecibels":true}"#, #"{"masterGainDecibels":[0]}"#,
        ]
        for json in badLevels {
            defaults.removePersistentDomain(forName: world.suiteName)
            stored(json)
            #expect(load().masterGainDecibels == -.infinity, "\(json): read louder than Silent")
        }
        // A level that can be what was left reads as itself.
        for (json, level) in [(#"{"masterGainDecibels":-12}"#, Float(-12)), (#"{"masterGainDecibels":0}"#, 0)] {
            defaults.removePersistentDomain(forName: world.suiteName)
            stored(json)
            #expect(load().masterGainDecibels == level)
        }
    }

    @Test("SETTINGS-06: Master Gain is never restored louder than it was left")
    func masterGainNeverLouder() {
        let silent = -Float.infinity
        let cases: [(json: String, level: Float)] = [
            ("-20", -20), ("0", MasterGainLaw.unity), (#""-Infinity""#, silent), ("-80", -80),
            ("6", silent), (#""+Infinity""#, silent), (#""NaN""#, silent), (#""loud""#, silent),
            ("null", silent), ("[]", silent),
        ]
        for (json, expected) in cases {
            stored(#"{"version":1,"masterGainDecibels":\#(json)}"#)
            #expect(load().masterGainDecibels == expected, "stored \(json)")
        }
    }

    @Test("SETTINGS-07: a value that can't be read is copied aside, and reads as the default with Master Gain Silent")
    func unreadableValue() {
        let garbage = Data("{not json".utf8)
        defaults.set(garbage, forKey: Self.key)
        #expect(load() == ListeningSettings(masterGainDecibels: -.infinity))
        #expect(defaults.data(forKey: Self.key + ".unreadable") == garbage)
        #expect(defaults.data(forKey: Self.key) == garbage, "left in place until a change overwrites it")
    }

    @Test("SETTINGS-08: R1's shuffle and repeat are taken in when there is no value yet, and left in place")
    func takesInR1() {
        defaults.set(true, forKey: "queue.cursor.shuffle")
        defaults.set(2, forKey: "queue.cursor.repeatMode")
        #expect(load() == ListeningSettings(shuffle: true, repeatMode: 2))
        #expect(defaults.object(forKey: "queue.cursor.shuffle") as? Bool == true, "a downgrade still finds them")

        defaults.set(9, forKey: "queue.cursor.repeatMode")
        #expect(load().repeatMode == 0, "out of range: off")

        // Once a value is stored, R1's keys are not read again.
        stored(#"{"version":1,"shuffle":false}"#)
        #expect(!load().shuffle)
    }
}
