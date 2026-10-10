// PIN — the "Used on <output>" pin (EQ4; decision 28, ui-plan §3.3, amendment 13): pinning keeps exactly
// what plays and gives the output a slot of its own; edits and Tone then stay with it; unpinning hands
// its sound to the shared slot; an output that can't be pinned never is; a second unit of the model
// shares the one pin (the model-UID fallback).

@testable import EQEditKit
import Foundation
import Testing

@Suite("Pins — pin, unpin, and what each output then plays")
struct EQPinTests {
    private static let speakers = EQOutputKey(uid: "BuiltInSpeakerDevice", modelUID: nil, name: "Speakers")
    private static let pods = EQOutputKey(uid: "A4-C3:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
    private static let secondPods = EQOutputKey(uid: "B8-00:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
    private static let aggregate = EQOutputKey(uid: "CADefaultDeviceAggregate-4242-0", modelUID: nil, name: "Agg")

    /// Warm with a dip drawn in and Presence +3: an edit and a Tone, both remembered by a pin.
    private static func editedWarmWithTone() -> EQState {
        var curve = EQCurve(points: EQBuiltInPreset.warm.points)
        curve.setPoint(22, to: -1.5)
        curve.setTone(.presence, to: 3)
        return EQState(preset: .builtIn(.warm), curve: curve)
    }

    @Test("PIN-01: pinning keeps exactly what plays, then the pinned output keeps its own edits and Tone")
    func pinKeepsWhatPlays() {
        let edited = Self.editedWarmWithTone()
        var store = EQStore(shared: edited)
        #expect(store.pin(for: Self.pods) == .unpinned(Self.pods))
        store.pin(Self.pods)
        #expect(store.pin(for: Self.pods) == .pinned(Self.pods))
        #expect(store[slot: store.slotID(for: Self.pods)] == edited, "nothing audible changes on pinning")
        // An edit on the pinned output stays there; the speakers keep the shared EQ.
        store[slot: store.slotID(for: Self.pods)] = EQState(preset: .builtIn(.vocal), curve: nil)
        #expect(store[slot: store.slotID(for: Self.speakers)] == edited)
        #expect(store[slot: store.slotID(for: Self.pods)].preset == .builtIn(.vocal))
        // Back on the pods later: exactly what was last heard there.
        #expect(store[slot: store.slotID(for: Self.pods)] == EQState(preset: .builtIn(.vocal), curve: nil))
    }

    @Test("PIN-02: the pin remembers edits and Tone through eqStateV2")
    func pinSurvivesTheStoredForm() throws {
        var store = EQStore(shared: .flat)
        store.pin(Self.pods)
        store[slot: Self.pods.uid] = Self.editedWarmWithTone()
        let decoded = try JSONDecoder().decode(EQStore.self, from: JSONEncoder().encode(store))
        #expect(decoded[slot: decoded.slotID(for: Self.pods)] == Self.editedWarmWithTone())
        #expect(decoded[slot: decoded.slotID(for: Self.pods)].resolvedCurve.tone(of: .presence) == 3)
        #expect(decoded.pin(for: Self.pods) == .pinned(Self.pods))
    }

    @Test("PIN-03: unpinning hands the pin's sound to the shared slot — no audible jump")
    func unpinKeepsTheSound() {
        var store = EQStore(shared: .flat)
        store.pin(Self.pods)
        store[slot: Self.pods.uid] = Self.editedWarmWithTone()
        store.unpin(Self.pods)
        #expect(store.pin(for: Self.pods) == .unpinned(Self.pods))
        #expect(store[slot: store.slotID(for: Self.pods)] == Self.editedWarmWithTone())
        #expect(store[slot: nil] == Self.editedWarmWithTone(), "the shared slot took it over")
        // Unpinning what plays shared already does nothing.
        let before = store
        store.unpin(Self.speakers)
        store.unpin(nil)
        #expect(store == before)
    }

    @Test("PIN-04: an output that can't be pinned never is — a private aggregate, no UID, no output")
    func unpinnableOutputs() {
        var store = EQStore(shared: Self.editedWarmWithTone())
        store.pin(Self.aggregate)
        store.pin(EQOutputKey(uid: "", modelUID: nil, name: "?"))
        #expect(store.pinned.isEmpty)
        #expect(store.pin(for: Self.aggregate) == nil)
        #expect(store.pin(for: nil) == nil)
    }

    @Test("PIN-05: a second unit of the pinned model shares the one pin — and its edits land there (amendment 13)")
    func sameModelSharesThePin() {
        var store = EQStore(shared: .flat)
        store.pin(Self.pods)
        store[slot: Self.pods.uid] = EQState(preset: .builtIn(.bassBoost), curve: nil)
        #expect(store.pin(for: Self.secondPods) == .sharedWith(Self.pods, on: Self.secondPods))
        #expect(store[slot: store.slotID(for: Self.secondPods)].preset == .builtIn(.bassBoost))
        // An edit on the second pair rewrites the first pair's memory: the documented behaviour.
        store[slot: store.slotID(for: Self.secondPods)] = EQState(preset: .builtIn(.vocal), curve: nil)
        #expect(store[slot: store.slotID(for: Self.pods)].preset == .builtIn(.vocal))
        // Pinning the second pair gives it its own copy; with two pins of the model, neither is shared.
        store.pin(Self.secondPods)
        #expect(store.pin(for: Self.secondPods) == .pinned(Self.secondPods))
        #expect(store[slot: store.slotID(for: Self.secondPods)].preset == .builtIn(.vocal))
    }

    @Test("PIN-06: unpinning from the second unit unpins the model's one pin — both play shared")
    func unpinFromTheSharingUnit() {
        var store = EQStore(shared: .flat)
        store.pin(Self.pods)
        store[slot: Self.pods.uid] = EQState(preset: .builtIn(.bassBoost), curve: nil)
        store.unpin(Self.secondPods)
        #expect(store.pinned.isEmpty)
        #expect(store.pin(for: Self.pods) == .unpinned(Self.pods))
        #expect(store[slot: nil].preset == .builtIn(.bassBoost))
    }

    @Test("PIN-07: pinning again is a no-op; pinning replaces an unreadable pin of the same UID")
    func pinTwiceAndOverUnreadable() throws {
        var store = EQStore(shared: .flat)
        store.pin(Self.pods)
        store[slot: Self.pods.uid] = EQState(preset: .builtIn(.vocal), curve: nil)
        store.pin(Self.pods)
        #expect(store[slot: Self.pods.uid].preset == .builtIn(.vocal), "a second pin keeps what the pin holds")
        // A pin this build can't read, under the pods' UID, is replaced when the pods are pinned again.
        let damaged = #"{"version":2,"shared":{"preset":{"builtIn":"Flat"},"isOn":true},"#
            + #""pinned":{"A4-C3:output":{"key":{"name":"x"},"state":{}}}}"#
        var reloaded = try EQFixture.decode(EQStore.self, damaged)
        #expect(reloaded.unreadablePins[Self.pods.uid] != nil)
        reloaded.pin(Self.pods)
        #expect(reloaded.unreadablePins[Self.pods.uid] == nil)
        #expect(reloaded.pin(for: Self.pods) == .pinned(Self.pods))
    }
}
