// BREAK-IT (EQ3a) — the adversarial pass over the kit (stored state, slots, choosing). Each test
// names the claim it attacks and is RED on purpose: product code is left unfixed for the builder.
// The view-model findings (strokes interleaved with discrete edits, the re-upgrade, Save across an
// output switch, the drag that freezes on an output change, the toast after a no-output gap) are
// reproduced against the real `EQViewModel` sources in the break-it report, not here: the app
// target is not importable from a test target.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQ3a break-it — the kit")
struct EQBreakItEQ3aTests {
    private static let pods = EQOutputKey(uid: "A4-C3:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
    private static let dac = EQOutputKey(uid: "USB:Modi:1", modelUID: "Modi+:30BE", name: "Modi+ USB DAC")

    /// `value` as a JSON object, to corrupt one field of a stored form the way a bad write would.
    private static func object(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private static func decode<T: Decodable>(_: T.Type, from object: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("BRK-01: one pin whose key cannot be read must not take every other pin with it")
    func oneUnreadablePinKeepsTheOthers() throws {
        // Two pins as this build writes them; then the DAC pin key loses its UID (a bad write, or a
        // later build that reshapes the key). The AirPods pin is intact and must still be found.
        let vocal = EQState(preset: .builtIn(.vocal), curve: nil)
        let warm = EQState(preset: .builtIn(.warm), curve: nil)
        let store = EQStore(shared: .flat, pinned: [
            Self.pods.uid: .init(key: Self.pods, state: vocal),
            Self.dac.uid: .init(key: Self.dac, state: warm),
        ])
        var stored = try Self.object(store)
        var pinned = try #require(stored["pinned"] as? [String: Any])
        var dacSlot = try #require(pinned[Self.dac.uid] as? [String: Any])
        dacSlot["key"] = ["name": "Modi+ USB DAC"]
        pinned[Self.dac.uid] = dacSlot
        stored["pinned"] = pinned
        let decoded = try Self.decode(EQStore.self, from: stored)
        // Today the whole pinned map is dropped, and the next write (any edit) makes that permanent.
        #expect(decoded.slotID(for: Self.pods) == Self.pods.uid, "the intact AirPods pin was dropped")
        #expect(decoded[slot: decoded.slotID(for: Self.pods)] == vocal)
    }

    @Test("BRK-02: a slot whose curve cannot be read keeps its Off (decision 25: Off is the bit-perfect path)")
    func unreadableCurveKeepsOff() throws {
        // An edited Warm, switched Off, whose stored curve is then damaged (a short base).
        var curve = EQCurve(points: EQBuiltInPreset.warm.points)
        curve.setPoint(20, to: 9)
        let off = EQState(preset: .builtIn(.warm), curve: curve, isOn: false)
        var state = try Self.object(off)
        state["curve"] = ["base": [1, 2, 3], "tone": [0, 0, 0, 0, 0]]
        var stored = try Self.object(EQStore(shared: .flat))
        stored["shared"] = state
        let decoded = try Self.decode(EQStore.self, from: stored)[slot: nil]
        // Today the slot becomes `.flat`, which is ON: a damaged curve silently turns the EQ on.
        #expect(decoded.isOn == false, "the slot was Off; it now plays \(decoded.preset.displayName), on")
    }

    @Test("BRK-03: choosing a malformed My Preset is nil (as for a missing one), never a crash")
    func choosingAMalformedMyPresetDoesNotTrap() async {
        // `EQState(choosing:myPresets:)` is public and documents nil for a preset that is not there;
        // the kit elsewhere tolerates a wrong-count preset (`isEdited` never matches it, the
        // migration skips it). Choosing one instead reaches `EQCurve.init(base:tone:)` precondition.
        await #expect(processExitsWith: .success) {
            _ = EQState(choosing: .mine("Short"), myPresets: ["Short": [1, 2, 3]])
        }
    }
}
