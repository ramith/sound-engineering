// STATE — one slot's state (EQ3a; amendment 8): an unedited built-in is a REFERENCE (no curve, so it
// plays the preset's current points and a re-voice reaches it), the form is canonical, a My Preset
// always carries its curve, and choosing / editing / saving follow the contract.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQState — a slot, with unedited built-ins as references")
struct EQStateTests {
    private static let lateNight = EQFixture.points([3: 5, 4: 6, 5: 5, 27: -3])
    private static let myPresets = ["Late Night": lateNight]

    /// One pinned slot as stored: `"uid": {"key": {...}, "state": state}`.
    private static func pinnedJSON(_ uid: String, _ name: String, _ state: String) -> String {
        #""\#(uid)":{"key":{"uid":"\#(uid)","name":"\#(name)"},"state":\#(state)}"#
    }

    @Test("STATE-01: a built-in whose curve plays the preset is stored as the reference")
    func canonicalReference() {
        let reference = EQState(preset: .builtIn(.warm), curve: nil)
        let warmCurve = EQCurve(points: EQBuiltInPreset.warm.points)
        #expect(EQState(preset: .builtIn(.warm), curve: warmCurve) == reference)
        // Within the 0.05 dB rule counts as the preset too.
        var near = EQBuiltInPreset.warm.points
        near[12] += 0.03
        #expect(EQState(preset: .builtIn(.warm), curve: EQCurve(points: near)).curve == nil)
        #expect(reference.points == EQBuiltInPreset.warm.points)
        #expect(!reference.isEdited(myPresets: [:]))
    }

    @Test("STATE-02: unedited built-ins encode with NO curve; edited states keep theirs")
    func encodedForms() throws {
        #expect(try EQFixture.json(EQState(preset: .builtIn(.warm), curve: nil))
            == #"{"isOn":true,"preset":{"builtIn":"Warm"}}"#)
        let edited = EQState(preset: .builtIn(.warm), curve: EQFixture.curve([20: 4]))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(edited))
        #expect(try Set(#require(object as? [String: Any]).keys) == ["preset", "curve", "isOn"])
        #expect(try EQFixture.json(EQPresetRef.mine("Late Night")) == #"{"mine":"Late Night"}"#)
    }

    @Test("STATE-03: re-voicing a built-in reaches unedited slots, shared and pinned — never edited ones")
    func revoicingReachesUneditedSlots() throws {
        // A store as an earlier build wrote it, before Warm was re-voiced: the unedited Warm slots
        // (shared, and pinned on "dac") store no points; the edited one ("pods") stores its own base —
        // the old voicing, 1 dB lower, plus the user's +3 dB at band 20.
        var editedBase = EQBuiltInPreset.warm.points.map { $0 - 1 }
        editedBase[20] += 3
        let unedited = #"{"preset":{"builtIn":"Warm"},"isOn":true}"#
        let edited = #"{"preset":{"builtIn":"Warm"},"isOn":true,"curve":{"base":"#
            + EQFixture.jsonArray(editedBase) + #","tone":[0,0,0,0,0]}}"#
        let stored = #"{"version":2,"shared":"# + unedited + #","pinned":{"#
            + Self.pinnedJSON("dac", "DAC", unedited) + "," + Self.pinnedJSON("pods", "AirPods", edited) + "}}"
        let store = try EQFixture.decode(EQStore.self, stored)
        // This build's voicing plays on both unedited slots…
        #expect(store[slot: nil].points == EQBuiltInPreset.warm.points)
        #expect(store[slot: "dac"].points == EQBuiltInPreset.warm.points)
        #expect(!store[slot: "dac"].isEdited(myPresets: [:]))
        // …while the edited slot plays exactly what the user made, still edited.
        #expect(EQFixture.close(store[slot: "pods"].points, editedBase))
        #expect(store[slot: "pods"].isEdited(myPresets: [:]))
    }

    @Test("STATE-04: a My Preset always carries its curve; one with none plays Flat")
    func myPresetCarriesItsCurve() {
        let saved = EQState(preset: .mine("Late Night"), curve: EQCurve(points: Self.lateNight))
        #expect(saved.curve != nil)
        #expect(!saved.isEdited(myPresets: Self.myPresets))
        #expect(saved.isEdited(myPresets: [:]), "a My Preset that no longer exists counts as edited")
        #expect(EQState(preset: .mine("Late Night"), curve: nil) == .flat)
    }

    @Test("STATE-05: choosing — a built-in by reference, a My Preset by its points, a missing one not at all")
    func choosing() throws {
        let vocal = EQState(choosing: .builtIn(.vocal), myPresets: [:])
        #expect(vocal == EQState(preset: .builtIn(.vocal), curve: nil))
        let mine = try #require(EQState(choosing: .mine("Late Night"), myPresets: Self.myPresets))
        #expect(mine.points == Self.lateNight && mine.isOn)
        #expect(EQState(choosing: .mine("Gone"), myPresets: Self.myPresets) == nil)
    }

    @Test("STATE-06: an edit turns the EQ on, and editing back onto the built-in restores the reference")
    func editing() {
        var state = EQState(preset: .builtIn(.warm), curve: nil, isOn: false)
        var curve = state.resolvedCurve
        curve.setPoint(20, to: 9)
        state.edit(to: curve)
        #expect(state.isOn)
        #expect(state.isEdited(myPresets: [:]))
        curve.setPoint(20, to: EQBuiltInPreset.warm.points[20])
        state.edit(to: curve)
        #expect(state == EQState(preset: .builtIn(.warm), curve: nil))
    }

    @Test("STATE-07: Save bakes the Tone into the My Preset, keeps the sound and on/off")
    func savingBakesTone() {
        var state = EQState(preset: .builtIn(.flat),
                            curve: EQCurve(base: EQFixture.points([10: 2]), tone: EQFixture.tone([.air: 4])),
                            isOn: false)
        let saved = state.saved(as: "Bright")
        #expect(saved.preset == .mine("Bright"))
        #expect(EQFixture.close(saved.points, state.points))
        #expect(saved.curve?.tone == EQFixture.tone([:]))
        #expect(!saved.isOn)
        #expect(!saved.isEdited(myPresets: ["Bright": saved.points]))
        state.isOn = true
        #expect(state.saved(as: "Bright").isOn)
    }

    @Test("STATE-08: decoding keeps the sound where it can — an unknown built-in plays on as an edited Flat")
    func lenientDecoding() throws {
        let curve = EQFixture.curve([4: 6])
        let podcast = try #"{"preset":{"builtIn":"Podcast"},"isOn":true,"curve":"# + EQFixture.json(curve) + "}"
        let decoded = try EQFixture.decode(EQState.self, podcast)
        #expect(decoded.preset == .builtIn(.flat))
        #expect(decoded.points == curve.points)
        #expect(try EQFixture.decode(EQState.self, #"{"preset":{"builtIn":"Podcast"},"isOn":false}"#)
            == EQState(preset: .builtIn(.flat), curve: nil, isOn: false))
        #expect(try EQFixture.decode(EQState.self, #"{"preset":{"mine":"Late Night"},"isOn":true}"#) == .flat)
        // A curve outside its limits throws (the store then plays Flat in that slot).
        let short = #"{"preset":{"builtIn":"Warm"},"isOn":true,"curve":{"base":[1],"tone":[0]}}"#
        #expect(throws: DecodingError.self) { try EQFixture.decode(EQState.self, short) }
    }
}
