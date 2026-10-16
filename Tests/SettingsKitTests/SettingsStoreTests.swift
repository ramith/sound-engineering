// SETTINGS — the listener's settings and their one store (R1.1-A, FD-2; council C-12, C-102, DEV-1):
// the faithful default, the round trip, a bad field read as its default, Master Gain never restored
// louder than it was left, R1's shuffle / repeat taken in once, and writes coalesced per main-actor turn.
// Over a defaults suite of its own, emptied before each test.

import EQEditKit
import Foundation
@testable import SettingsKit
import Testing

@MainActor
@Suite("SettingsStore — the listener's settings, kept", .serialized)
struct SettingsStoreTests {
    private static let suiteName = "SettingsKitTests"
    private static let key = "listeningSettingsV1"

    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    private func stored(_ json: String) {
        defaults.set(Data(json.utf8), forKey: Self.key)
    }

    private func load() -> ListeningSettings {
        SettingsStore(defaults: defaults).load()
    }

    /// Let the main actor finish this turn's work (a store's end-of-turn write).
    private func endTurn() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
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
        await endTurn()
        #expect(load() == Self.changed, "the turn's newest settings, written once it ended")

        // The faithful default saved over a new install's: equal to what is stored, so never written.
        defaults.removePersistentDomain(forName: Self.suiteName)
        let fresh = SettingsStore(defaults: defaults)
        fresh.save(fresh.load())
        await endTurn()
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
        #expect(settings.masterGainDecibels == MasterGainLaw.unity, "never stored: unity")

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
