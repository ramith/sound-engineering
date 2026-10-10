// BRING — "Bring back edits" (EQ3; decision 27, ui-plan §4.5): a switch away from an edited slot sets
// the whole slot aside; auditioning presets after it keeps offering the ORIGINAL edits, re-armed; a
// reset (re-choosing the preset playing) offers nothing new.

@testable import EQEditKit
import Testing

@Suite("EQBringBack — edits set aside by a preset switch")
struct EQBringBackTests {
    private static let myPresets = ["Late Night": EQFixture.points([3: 5, 27: -3])]

    /// Warm with one point moved (edited), switched off — the whole slot is what comes back.
    private static let editedWarm: EQState = {
        var points = EQBuiltInPreset.warm.points
        points[22] = 2 // a lift where Warm dips
        return EQState(preset: .builtIn(.warm), curve: EQCurve(points: points), isOn: false)
    }()

    @Test("BRING-01: leaving an edited slot for another preset sets the whole slot aside")
    func editedSwitchOffers() throws {
        let offer = try #require(EQBringBack.afterSwitch(from: nil, leaving: Self.editedWarm, to: .builtIn(.vocal),
                                                         myPresets: Self.myPresets))
        #expect(offer.edits == Self.editedWarm) // preset, curve AND On/Off
        #expect(offer.offer == 1)
        #expect(Self.editedWarm.offersBringBack(switchingTo: .mine("Late Night"), myPresets: Self.myPresets))
    }

    @Test("BRING-02: an unedited slot offers nothing; a reset (its own preset) offers nothing")
    func nothingToOffer() {
        let warm = EQState(preset: .builtIn(.warm), curve: nil)
        #expect(EQBringBack.afterSwitch(from: nil, leaving: warm, to: .builtIn(.vocal), myPresets: [:]) == nil)
        #expect(!Self.editedWarm.offersBringBack(switchingTo: .builtIn(.warm), myPresets: [:]))
        #expect(EQBringBack.afterSwitch(from: nil, leaving: Self.editedWarm, to: .builtIn(.warm),
                                        myPresets: [:]) == nil)
    }

    @Test("BRING-03: auditioning presets keeps the ORIGINAL edits and re-arms the offer each switch")
    func auditionKeepsOriginal() throws {
        let first = try #require(EQBringBack.afterSwitch(from: nil, leaving: Self.editedWarm, to: .builtIn(.vocal),
                                                         myPresets: [:]))
        let vocal = try #require(EQState(choosing: .builtIn(.vocal), myPresets: [:]))
        let second = try #require(EQBringBack.afterSwitch(from: first, leaving: vocal, to: .builtIn(.clarity),
                                                          myPresets: [:]))
        #expect(second.edits == Self.editedWarm)
        #expect(second.offer == first.offer + 1)
        // Back onto the set-aside preset itself, unedited: still offered, re-armed again.
        let clarity = try #require(EQState(choosing: .builtIn(.clarity), myPresets: [:]))
        let third = try #require(EQBringBack.afterSwitch(from: second, leaving: clarity, to: .builtIn(.warm),
                                                         myPresets: [:]))
        #expect(third.edits == Self.editedWarm && third.offer == second.offer + 1)
        // Re-choosing the preset already playing changes nothing.
        #expect(EQBringBack.afterSwitch(from: third, leaving: clarity, to: .builtIn(.clarity), myPresets: [:])
            == third)
    }

    @Test("BRING-04: leaving NEW edits replaces the ones set aside earlier")
    func newEditsReplace() throws {
        let first = try #require(EQBringBack.afterSwitch(from: nil, leaving: Self.editedWarm, to: .builtIn(.vocal),
                                                         myPresets: [:]))
        let editedVocal = EQState(preset: .builtIn(.vocal), curve: EQFixture.curve([10: 4]))
        let second = try #require(EQBringBack.afterSwitch(from: first, leaving: editedVocal, to: .builtIn(.flat),
                                                          myPresets: [:]))
        #expect(second.edits == editedVocal)
        #expect(second.offer == first.offer + 1)
    }
}
