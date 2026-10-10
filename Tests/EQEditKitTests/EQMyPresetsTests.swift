// MINE — My Presets (EQ4; break-it C1, N1, N2): what a preset may be called, Save into the slot the
// sheet opened on even after an output switch, Rename and Delete with every slot following, and edits
// set aside following a rename or delete.

@testable import EQEditKit
import Testing

@Suite("My Presets — names, Save (C1), Rename, Delete")
struct EQMyPresetsTests {
    private static let speakers = EQOutputKey(uid: "BuiltInSpeakerDevice", modelUID: nil, name: "Speakers")
    private static let pods = EQOutputKey(uid: "A4-C3:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
    private static let lateNight = EQFixture.points([3: 5, 4: 6, 5: 5, 27: -3])

    /// Edited Warm on the speakers (shared), the AirPods pinned to Vocal: break-it C1's world.
    private static func c1World() -> EQStore {
        var curve = EQCurve(points: EQBuiltInPreset.warm.points)
        curve.setPoint(22, to: -1.5)
        curve.setTone(.air, to: 2)
        var store = EQStore(shared: EQState(preset: .builtIn(.warm), curve: curve))
        store.pin(pods)
        store[slot: pods.uid] = EQState(preset: .builtIn(.vocal), curve: nil)
        return store
    }

    // MARK: Names (N1, N2)

    @Test("MINE-01: empty, space-only and line-break-only names are refused (N2)")
    func emptyNames() {
        for typed in ["", " ", "   ", "\n", " \n\t ", "\r\n"] {
            #expect(EQPresetName.check(typed, among: [String]()) == .invalid(.empty), "\(typed.debugDescription)")
        }
    }

    @Test("MINE-02: a built-in's name is refused in any case — display names, stored ids, retired ids (N1)")
    func builtInNames() {
        let reserved = ["Warm", "warm", "  WARM ", "Flat", "Bass & Treble", "bass & treble", "Bass Boost",
                        "BASS BOOST", "BassBoost", "Loudness", "loudness", "Studio", "studio", "STUDIO"]
        for typed in reserved {
            guard case let .invalid(.builtIn(name)) = EQPresetName.check(typed, among: [String]()) else {
                Issue.record("\(typed) was accepted")
                continue
            }
            #expect(name.caseInsensitiveCompare(typed.trimmingCharacters(in: .whitespaces)) == .orderedSame)
        }
        #expect(EQPresetName.check("Warmer", among: [String]()) == .new("Warmer"))
        #expect(EQPresetName.check("Bass", among: [String]()) == .new("Bass"))
        #expect(EQPresetName.Problem.builtIn("Studio").message
            == "“Studio” is reserved for a built-in preset. Choose another name.")
    }

    @Test("MINE-03: a name is one trimmed line; saving onto one of My Presets replaces it under its own name")
    func namesAndReplacing() {
        #expect(EQPresetName.check("  Late\nNight \n", among: [String]()) == .new("Late Night"))
        #expect(EQPresetName.check("late night", among: ["Late Night"]) == .replaces("Late Night"))
        #expect(EQPresetName.check("Late Night", among: ["Late Night"]) == .replaces("Late Night"))
    }

    @Test("MINE-04: renaming onto another of My Presets is refused; onto its own name, in any case, is fine")
    func renameNames() {
        let names = ["Late Night", "Podcast"]
        #expect(EQPresetName.check("podcast", among: names, renaming: "Late Night") == .invalid(.taken("Podcast")))
        #expect(EQPresetName.check("late night", among: names, renaming: "Late Night") == .new("late night"))
        #expect(EQPresetName.check("Late Night", among: names, renaming: "Late Night") == .new("Late Night"))
        #expect(EQPresetName.check("Warm", among: names, renaming: "Late Night") == .invalid(.builtIn("Warm")))
    }

    // MARK: Save (C1)

    @Test("MINE-05: Save after the output switched saves the curve shown at open, into the slot it came from (C1)")
    func saveIntoTheSlotItCameFrom() throws {
        var store = Self.c1World()
        var myPresets: [String: [Float]] = [:]
        // The sheet opens on the speakers; the AirPods connect while it is up.
        let source = store.saveSource(for: Self.speakers)
        let shown = store[slot: store.slotID(for: Self.speakers)].points
        let saved = EQMyPresets.save(source, as: "My Warm", store: &store, myPresets: &myPresets)
        #expect(saved == "My Warm")
        let points = try #require(myPresets["My Warm"])
        #expect(EQFixture.close(points, shown), "the edited Warm the user was looking at, Tone baked in")
        #expect(store[slot: nil] == EQState(preset: .mine("My Warm"), curve: EQCurve(points: points)))
        #expect(store[slot: Self.pods.uid] == EQState(preset: .builtIn(.vocal), curve: nil), "AirPods untouched")
    }

    @Test("MINE-06: Save refuses a bad name and changes nothing; onto an existing name it replaces it")
    func saveNames() {
        var store = Self.c1World()
        var myPresets = ["Late Night": Self.lateNight]
        let before = (store, myPresets)
        #expect(EQMyPresets.save(store.saveSource(for: Self.speakers), as: "warm", store: &store, myPresets: &myPresets)
            == nil)
        #expect(EQMyPresets.save(store.saveSource(for: Self.speakers), as: " \n", store: &store, myPresets: &myPresets)
            == nil)
        #expect(store == before.0 && myPresets == before.1)
        let saved = EQMyPresets.save(store.saveSource(for: Self.pods), as: "LATE NIGHT", store: &store,
                                     myPresets: &myPresets)
        #expect(saved == "Late Night")
        #expect(myPresets.keys.sorted() == ["Late Night"])
        #expect(myPresets["Late Night"] == EQBuiltInPreset.vocal.points)
        #expect(store[slot: Self.pods.uid].preset == .mine("Late Night"))
    }

    // MARK: Rename and Delete

    @Test("MINE-07: rename moves the preset and every slot playing it, shared and pinned")
    func renameFollows() {
        var store = EQStore(shared: EQState(preset: .mine("Late Night"), curve: EQCurve(points: Self.lateNight)))
        store.pin(Self.pods)
        var myPresets = ["Late Night": Self.lateNight, "Podcast": EQFixture.points([20: 3])]
        #expect(EQMyPresets.rename("Late Night", to: "Bedtime", store: &store, myPresets: &myPresets) == "Bedtime")
        #expect(myPresets.keys.sorted() == ["Bedtime", "Podcast"])
        #expect(myPresets["Bedtime"] == Self.lateNight)
        #expect(store[slot: nil].preset == .mine("Bedtime") && store[slot: Self.pods.uid].preset == .mine("Bedtime"))
        #expect(!store[slot: nil].isEdited(myPresets: myPresets))
        // Refused names and missing presets change nothing.
        let before = (store, myPresets)
        #expect(EQMyPresets.rename("Bedtime", to: "podcast", store: &store, myPresets: &myPresets) == nil)
        #expect(EQMyPresets.rename("Bedtime", to: "Vocal", store: &store, myPresets: &myPresets) == nil)
        #expect(EQMyPresets.rename("Gone", to: "Anything", store: &store, myPresets: &myPresets) == nil)
        #expect(store == before.0 && myPresets == before.1)
    }

    @Test("MINE-08: delete keeps every slot's sound, as an edited Flat")
    func deleteKeepsTheSound() {
        var store = EQStore(shared: EQState(preset: .mine("Late Night"), curve: EQCurve(points: Self.lateNight)))
        store.pin(Self.pods)
        var myPresets = ["Late Night": Self.lateNight]
        EQMyPresets.delete("Late Night", store: &store, myPresets: &myPresets)
        #expect(myPresets.isEmpty)
        for id in [nil, Self.pods.uid] {
            #expect(store[slot: id].preset == .builtIn(.flat))
            #expect(store[slot: id].points == Self.lateNight)
            #expect(store[slot: id].isEdited(myPresets: myPresets))
        }
    }

    @Test("MINE-09: edits set aside follow a rename, and keep their sound through a delete")
    func bringBackFollows() {
        let edits = EQState(preset: .mine("Late Night"), curve: EQCurve(points: EQFixture.points([4: 9])))
        let offer = EQBringBack(edits: edits, offer: 3)
        let renamed = offer.repointingMyPresets { $0 == "Late Night" ? "Bedtime" : $0 }
        #expect(renamed.edits.preset == .mine("Bedtime") && renamed.offer == 3)
        let deleted = offer.repointingMyPresets { $0 == "Late Night" ? nil : $0 }
        #expect(deleted.edits.preset == .builtIn(.flat) && deleted.edits.points == edits.points)
    }
}
