// LEVEL-SET — the Leveling setting, kept (R1.1-B, US-R1F-10 item 1; FD-2): Off on a new install, the listener's
// choice back after a relaunch, and a stored value this build can't read — a word it doesn't know, a number, a
// null — read as Off, costing no other setting. Over a defaults suite of its own, emptied before each test.

import Foundation
import RigKit
@testable import SettingsKit
import Testing

@MainActor
@Suite("Leveling — the setting, kept", .timeLimit(.minutes(3)))
struct LevelingSettingTests {
    private static let key = "listeningSettingsV1"

    /// The suite of this test's own, removed with it.
    private let world = IsolatedDefaults("LevelingSettingTests")
    private var defaults: UserDefaults {
        world.defaults
    }

    private func stored(_ json: String) {
        defaults.set(Data(json.utf8), forKey: Self.key)
    }

    private func load() -> ListeningSettings {
        SettingsStore(defaults: defaults).load()
    }

    @Test("LEVEL-SET-01: a new install levels nothing (FD-2), and an R1.1-A value without the field reads Off")
    func offByDefault() {
        #expect(load().leveling == .off)
        #expect(ListeningSettings.faithful.leveling == .off)
        stored(#"{"version":1,"masterGainDecibels":-6,"crossfeed":true}"#)
        let earlier = load()
        #expect(earlier.leveling == .off, "a value written before Leveling existed")
        #expect(earlier.masterGainDecibels == -6 && earlier.crossfeed, "the fields it has still read")
    }

    @Test("LEVEL-SET-02: each choice is what the next launch reads", arguments: LevelingSetting.allCases)
    func roundTrip(choice: LevelingSetting) {
        let store = SettingsStore(defaults: defaults)
        _ = store.load()
        var settings = ListeningSettings(masterGainDecibels: -3)
        settings.leveling = choice
        store.save(settings)
        store.flush()
        #expect(load() == settings)
    }

    @Test("LEVEL-SET-03: stored as its word, so a reorder of the cases can never change what comes back")
    func storedForm() throws {
        let store = SettingsStore(defaults: defaults)
        _ = store.load()
        var settings = ListeningSettings()
        settings.leveling = .album
        store.save(settings)
        store.flush()
        let data = try #require(defaults.data(forKey: Self.key))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["leveling"] as? String == "album")
        #expect(LevelingSetting.allCases.map(\.rawValue) == ["off", "auto", "album", "track"])
    }

    @Test("LEVEL-SET-04: a value this build can't read is Off, and every other field still reads",
          arguments: [#""loudest""#, "2", "null", #""AUTO""#, "true", #"{"mode":"auto"}"#])
    func badValueReadsOff(bad: String) {
        stored(#"{"version":1,"masterGainDecibels":-9,"shuffle":true,"leveling":\#(bad)}"#)
        let settings = load()
        #expect(settings.leveling == .off, "\(bad)")
        #expect(settings.masterGainDecibels == -9 && settings.shuffle, "one bad field never costs the others")
    }
}
