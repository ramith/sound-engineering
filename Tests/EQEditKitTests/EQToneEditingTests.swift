// TONE-EDIT — Tone as an edit (EQ3t; decision 24: a macro over the 31 points, not a second mode):
// setTone moves the points by the region's weights and never the base, it is held in ±12, resetTone
// takes exactly that back, the ceiling's held points are counted, a preset choice puts Tone back to
// 0, Save bakes it in, and it survives the `eqStateV2` round trip.

@testable import EQEditKit
import Foundation
import Testing

@Suite("Tone — setTone, resetTone, the clamp, presets, Save and eqStateV2")
struct EQToneEditingTests {
    /// A user's own layer: a different level at every band, inside ±12.
    private static let base: [Float] = (0 ..< EQBands.count).map { Float($0 % 9) - 4 }

    @Test("TONE-EDIT-01: setTone moves each point by the region's weight there, and leaves the base")
    func setToneMovesPointsByWeight() {
        var curve = EQCurve(base: Self.base, tone: EQFixture.tone([:]))
        curve.setTone(.presence, to: 3)
        let weights = EQToneRegion.bandWeights[EQToneRegion.presence.rawValue]
        for band in 0 ..< EQBands.count {
            #expect(abs(curve.points[band] - (Self.base[band] + 3 * weights[band])) <= EQFixture.tolerance,
                    "band \(band)")
        }
        #expect(curve.base == Self.base)
        #expect(curve.tone(of: .presence) == 3)
        #expect(curve.tone == EQFixture.tone([.presence: 3]))
        // A second region adds its own share; the first keeps its level.
        curve.setTone(.bass, to: -2)
        #expect(curve.tone == EQFixture.tone([.presence: 3, .bass: -2]))
        #expect(curve.hasTone)
    }

    @Test("TONE-EDIT-02: Tone is held in ±12 dB; a non-finite level is ignored")
    func setToneClamps() {
        var curve = EQCurve.flat
        curve.setTone(.air, to: 30)
        #expect(curve.tone(of: .air) == 12)
        curve.setTone(.air, to: -12.5)
        #expect(curve.tone(of: .air) == -12)
        for bad: Float in [.nan, .infinity, -.infinity] {
            curve.setTone(.air, to: bad)
            #expect(curve.tone(of: .air) == -12, "\(bad) must not land")
        }
        // A point is still held in ±12 whatever Tone asks: all five at +12 on a +6 base.
        var loud = EQCurve(base: [Float](repeating: 6, count: EQBands.count), tone: EQFixture.tone([:]))
        for region in EQToneRegion.allCases {
            loud.setTone(region, to: 12)
        }
        #expect(loud.points.allSatisfy { $0 == 12 })
    }

    @Test("TONE-EDIT-03: resetTone takes Tone back exactly — the points are the base again")
    func resetToneRestoresTheBase() {
        var curve = EQCurve(base: Self.base, tone: EQFixture.tone([:]))
        let before = curve
        curve.setTone(.bass, to: 7.5)
        curve.setTone(.mids, to: -4)
        curve.setTone(.air, to: 12)
        #expect(curve != before)
        curve.resetTone()
        #expect(curve == before)
        #expect(curve.points == Self.base)
        #expect(!curve.hasTone)
        // A point set under Tone keeps where the user put it in the base: Reset Tone then moves
        // that point by exactly the Tone it had (Tone is a layer, not a one-way bake).
        var layered = EQCurve.flat
        layered.setTone(.mids, to: 6)
        layered.setPoint(17, to: 2) // 1 kHz is all Mids: base = 2 − 6 = −4
        layered.resetTone()
        #expect(abs(layered.points[17] + 4) <= EQFixture.tolerance)
    }

    @Test("TONE-EDIT-04: the points the ceiling holds are counted — only inside the region's reach")
    func heldPointsAreCounted() {
        // Every point already at +12: any lift in a region holds exactly the bands it reaches.
        let ceiling = [Float](repeating: 12, count: EQBands.count)
        var curve = EQCurve(base: ceiling, tone: EQFixture.tone([:]))
        #expect(EQToneRegion.allCases.allSatisfy { curve.heldPointCount(in: $0) == 0 },
                "at the ceiling but asking no more: nothing held")
        curve.setTone(.bass, to: 1)
        let bassReach = EQToneRegion.bandWeights[EQToneRegion.bass.rawValue].count { $0 > 0 }
        #expect(curve.heldPointCount(in: .bass) == bassReach)
        #expect(curve.heldPointCount(in: .air) == 0, "Air reaches none of the held bass bands")
        // The floor holds too: a base of −20 lifted +6 still asks −14 of a point.
        var floor = EQCurve(base: [Float](repeating: -20, count: EQBands.count), tone: EQFixture.tone([:]))
        floor.setTone(.presence, to: 6)
        let presenceReach = EQToneRegion.bandWeights[EQToneRegion.presence.rawValue].count { $0 > 0 }
        #expect(floor.heldPointCount(in: .presence) == presenceReach)
    }

    @Test("TONE-EDIT-05: a Tone move is an edit — it turns the EQ on; Reset Tone is the preset again")
    func toneIsAnEdit() {
        var state = EQState(preset: .builtIn(.warm), curve: nil, isOn: false)
        var curve = state.resolvedCurve
        curve.setTone(.presence, to: 3)
        state.edit(to: curve)
        #expect(state.isOn)
        #expect(state.isEdited(myPresets: [:]))
        curve.resetTone()
        state.edit(to: curve)
        #expect(state == EQState(preset: .builtIn(.warm), curve: nil), "back to the unedited reference")
    }

    @Test("TONE-EDIT-06: choosing a preset puts Tone back to 0 (\"Vocal starts clean\")")
    func choosingResetsTone() throws {
        var curve = EQState(preset: .builtIn(.warm), curve: nil).resolvedCurve
        curve.setTone(.air, to: 4)
        var state = EQState(preset: .builtIn(.warm), curve: nil)
        state.edit(to: curve)
        #expect(state.resolvedCurve.hasTone)
        let vocal = try #require(EQState(choosing: .builtIn(.vocal), myPresets: [:]))
        #expect(!vocal.resolvedCurve.hasTone)
        #expect(vocal.points == EQBuiltInPreset.vocal.points)
        // Re-choosing the same preset resets its Tone too.
        let warm = try #require(EQState(choosing: .builtIn(.warm), myPresets: [:]))
        #expect(!warm.resolvedCurve.hasTone && !warm.isEdited(myPresets: [:]))
        // A My Preset as well.
        let mine = try #require(EQState(choosing: .mine("Late"), myPresets: ["Late": EQFixture.points([4: 5])]))
        #expect(!mine.resolvedCurve.hasTone)
    }

    @Test("TONE-EDIT-07: Save bakes Tone into the saved points — same sound, Tone at 0, unedited")
    func saveBakesTone() {
        var curve = EQState(preset: .builtIn(.clarity), curve: nil).resolvedCurve
        curve.setTone(.bass, to: 5)
        curve.setTone(.presence, to: -2.5)
        var state = EQState(preset: .builtIn(.clarity), curve: nil)
        state.edit(to: curve)
        let saved = state.saved(as: "Clear Bass")
        #expect(saved.preset == .mine("Clear Bass"))
        #expect(EQFixture.close(saved.points, state.points))
        #expect(!saved.resolvedCurve.hasTone)
        #expect(!saved.isEdited(myPresets: ["Clear Bass": saved.points]))
    }

    @Test("TONE-EDIT-08: Tone round-trips through eqStateV2 — shared and pinned, level for level")
    func toneRoundTrips() throws {
        var warm = EQState(preset: .builtIn(.warm), curve: nil).resolvedCurve
        warm.setTone(.presence, to: 3)
        var shared = EQState(preset: .builtIn(.warm), curve: nil)
        shared.edit(to: warm)
        var flat = EQCurve.flat
        flat.setTone(.bass, to: -7.5)
        flat.setTone(.air, to: 12)
        let pods = EQOutputKey(uid: "A4-C3:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
        let store = EQStore(shared: shared, pinned: [
            pods.uid: .init(key: pods, state: EQState(preset: .builtIn(.flat), curve: flat, isOn: false)),
        ])
        let decoded = try JSONDecoder().decode(EQStore.self, from: JSONEncoder().encode(store))
        #expect(decoded == store)
        #expect(decoded[slot: nil].resolvedCurve.tone(of: .presence) == 3)
        #expect(decoded[slot: pods.uid].resolvedCurve.tone == EQFixture.tone([.bass: -7.5, .air: 12]))
        #expect(decoded[slot: pods.uid].points == flat.points)
        // The stored form carries the Tone layer itself, never the points it makes.
        #expect(try EQFixture.json(shared).contains(#""tone":[0,0,0,3,0]"#))
    }
}
