// STORE — the persisted aggregate `eqStateV2` (EQ3a; review F5/F8): slot resolution (exact UID,
// then the model-UID fallback only when exactly one pin has it; never for an output that can't be
// pinned), reads and writes to the right slot, the My Preset fix-ups (rename, delete, and a
// reference left dangling at load), and the stored form with its lenient fallbacks.

@testable import EQEditKit
import Foundation
import Testing

@Suite("EQStore — slots, resolution, fix-ups, the stored form")
struct EQStoreTests {
    private static let pods = EQOutputKey(uid: "A4-C3:output", modelUID: "AirPods Pro,2", name: "AirPods Pro")
    private static let dac = EQOutputKey(uid: "USB:Modi:1", modelUID: "Modi+:30BE", name: "Modi+ USB DAC")
    private static let speakers = EQOutputKey(uid: "BuiltInSpeakerDevice", modelUID: nil, name: "Speakers")
    private static let vocal = EQState(preset: .builtIn(.vocal), curve: nil)
    private static let warm = EQState(preset: .builtIn(.warm), curve: nil)

    private static func store(pinning keys: [EQOutputKey], shared: EQState = .flat) -> EQStore {
        EQStore(shared: shared, pinned: Dictionary(uniqueKeysWithValues: keys.map {
            ($0.uid, EQStore.PinnedSlot(key: $0, state: vocal))
        }))
    }

    @Test("STORE-01: an output plays its own pin by exact UID; anything unpinned plays shared")
    func exactUID() {
        let store = Self.store(pinning: [Self.pods])
        #expect(store.slotID(for: Self.pods) == Self.pods.uid)
        #expect(store.slotID(for: Self.speakers) == nil)
        #expect(store.slotID(for: nil) == nil)
        #expect(store[slot: store.slotID(for: Self.pods)] == Self.vocal)
        #expect(store[slot: store.slotID(for: Self.speakers)] == .flat)
    }

    @Test("STORE-02: another unit of a pinned model plays that pin — only when exactly one pin has the model")
    func modelUIDFallback() {
        let secondPair = EQOutputKey(uid: "B8-00:output", modelUID: Self.pods.modelUID, name: "AirPods Pro")
        #expect(Self.store(pinning: [Self.pods, Self.dac]).slotID(for: secondPair) == Self.pods.uid)
        // Two pins of the model: ambiguous, so shared.
        let thirdPair = EQOutputKey(uid: "C9-11:output", modelUID: Self.pods.modelUID, name: "AirPods Pro")
        #expect(Self.store(pinning: [Self.pods, thirdPair]).slotID(for: secondPair) == nil)
        // No model UID to fall back on.
        let unknownModel = EQOutputKey(uid: "X:output", modelUID: nil, name: "Headphones")
        #expect(Self.store(pinning: [Self.pods]).slotID(for: unknownModel) == nil)
    }

    @Test("STORE-03: an output that can't be pinned (a per-launch private aggregate, no UID) plays shared")
    func unpinnableOutputsPlayShared() {
        let aggregate = EQOutputKey(uid: "CADefaultDeviceAggregate-4242-0", modelUID: "aggregate", name: "Aggregate")
        let noUID = EQOutputKey(uid: "", modelUID: "aggregate", name: "?")
        #expect(!aggregate.isPinnable && !noUID.isPinnable && Self.pods.isPinnable)
        // Even a pin carrying that exact UID or model UID is never resolved.
        let store = Self.store(pinning: [aggregate, EQOutputKey(uid: "Y", modelUID: "aggregate", name: "Y")])
        #expect(store.slotID(for: aggregate) == nil)
        #expect(store.slotID(for: noUID) == nil)
    }

    @Test("STORE-04: a write lands in its own slot only; an unknown slot is the shared one")
    func writesStayInTheirSlot() {
        var store = Self.store(pinning: [Self.pods, Self.dac])
        store[slot: Self.pods.uid] = Self.warm
        #expect(store[slot: Self.pods.uid] == Self.warm)
        #expect(store[slot: Self.dac.uid] == Self.vocal)
        #expect(store[slot: nil] == .flat)
        store[slot: "not pinned"] = Self.warm
        #expect(store.shared == Self.warm)
        #expect(store.pinned.count == 2)
    }

    @Test("STORE-05: rename re-points every slot on the preset, curves kept; others untouched")
    func renameFixUp() {
        let curve = EQFixture.curve([6: 4])
        let late = EQState(preset: .mine("Late"), curve: curve)
        var store = EQStore(shared: late, pinned: [
            Self.pods.uid: .init(key: Self.pods, state: late),
            Self.dac.uid: .init(key: Self.dac, state: EQState(preset: .mine("Other"), curve: curve)),
        ])
        store.repointMyPresets { $0 == "Late" ? "Late Night" : $0 }
        let renamed = EQState(preset: .mine("Late Night"), curve: curve)
        #expect(store[slot: nil] == renamed && store[slot: Self.pods.uid] == renamed)
        #expect(store[slot: Self.dac.uid].preset == .mine("Other"))
    }

    @Test("STORE-06: delete — and a reference dangling at load — leaves an edited Flat with the curve kept")
    func deleteAndDanglingFixUp() {
        let curve = EQFixture.curve([6: 4, 7: 2])
        var store = EQStore(shared: EQState(preset: .mine("Gone"), curve: curve), pinned: [
            Self.pods.uid: .init(key: Self.pods, state: EQState(preset: .mine("Kept"), curve: curve)),
            Self.dac.uid: .init(key: Self.dac, state: EQState(preset: .mine("Flat One"), curve: .flat)),
        ])
        // The load-time rule: names that no longer exist resolve to nil.
        let myPresets: [String: [Float]] = ["Kept": curve.points]
        store.repointMyPresets { myPresets[$0] == nil ? nil : $0 }
        #expect(store[slot: nil].preset == .builtIn(.flat))
        #expect(store[slot: nil].points == curve.points)
        #expect(store[slot: nil].isEdited(myPresets: myPresets))
        #expect(store[slot: Self.pods.uid].preset == .mine("Kept"))
        #expect(store[slot: Self.dac.uid] == .flat, "a deleted preset that was flat is plain Flat")
    }

    @Test("STORE-07: the stored form — {version 2, shared, pinned by UID} — and its round trip")
    func storedForm() throws {
        #expect(try EQFixture.json(EQStore(shared: Self.warm))
            == #"{"pinned":{},"shared":{"isOn":true,"preset":{"builtIn":"Warm"}},"version":2}"#)
        var store = Self.store(pinning: [Self.pods, Self.speakers], shared: Self.warm)
        store[slot: Self.speakers.uid] = EQState(preset: .mine("Late"), curve: EQFixture.curve([2: -3]))
        #expect(try JSONDecoder().decode(EQStore.self, from: JSONEncoder().encode(store)) == store)
    }

    @Test("STORE-08: another version throws; a state that can't be read plays Flat without losing the rest")
    func lenientDecoding() throws {
        #expect(throws: DecodingError.self) {
            try EQFixture.decode(EQStore.self, #"{"version":3,"shared":{"preset":{"builtIn":"Warm"},"isOn":true}}"#)
        }
        let bad = #"["not a state"]"#
        let good = #"{"preset":{"builtIn":"Vocal"},"isOn":true}"#
        let pin = #""p":{"key":{"uid":"p","name":"P"},"state":"#
        let store = try EQFixture.decode(EQStore.self, #"{"version":2,"shared":"# + bad + #","pinned":{"#
            + pin + good + "}," + pin.replacingOccurrences(of: "\"p\"", with: "\"q\"") + bad + "}}}")
        #expect(store[slot: nil] == .flat)
        #expect(store[slot: "p"] == Self.vocal)
        #expect(store.pinned["q"]?.state == .flat, "the pin is kept, playing Flat")
        // Missing pins read as none.
        #expect(try EQFixture.decode(EQStore.self, #"{"version":2,"shared":"# + good + "}").pinned.isEmpty)
    }

    @Test("STORE-09: a pin that can't be read is kept aside and written back unchanged; pinning its UID replaces it")
    func unreadablePinIsKeptVerbatim() throws {
        let good = #"{"key":{"uid":"p","name":"P"},"state":{"isOn":true,"preset":{"builtIn":"Vocal"}}}"#
        let reshaped = #"{"key":{"id":7,"label":["Modi",null,true,1.5]},"state":{"x":1}}"#
        let stored = #"{"version":2,"shared":{"isOn":true,"preset":{"builtIn":"Warm"}},"pinned":{"p":"#
            + good + #","q":"# + reshaped + "}}"
        let store = try EQFixture.decode(EQStore.self, stored)
        #expect(store[slot: "p"] == Self.vocal && store.pinned.count == 1)
        #expect(store.unreadablePins.keys.sorted() == ["q"])
        // The next write keeps it exactly, so a build that can read it finds it again.
        let rewritten = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store)) as? [String: Any]
        let pins = try #require(rewritten?["pinned"] as? [String: Any])
        let expected = try JSONSerialization.jsonObject(with: Data(reshaped.utf8)) as? NSDictionary
        #expect((pins["q"] as? NSDictionary) == expected)
        #expect(try JSONDecoder().decode(EQStore.self, from: JSONEncoder().encode(store)) == store)
        // Pinning that UID again replaces the unreadable entry.
        let repinned = EQStore(shared: .flat, pinned: ["q": .init(key: Self.dac, state: Self.warm)],
                               unreadablePins: store.unreadablePins)
        let reread = try JSONDecoder().decode(EQStore.self, from: JSONEncoder().encode(repinned))
        #expect(reread.pinned["q"]?.state == Self.warm && reread.unreadablePins.isEmpty)
    }

    @Test("STORE-10: a slot change is a move to another slot — never a move between outputs that share one")
    func slotChange() {
        let store = Self.store(pinning: [Self.pods])
        #expect(!store.isSlotChange(from: Self.speakers, to: Self.dac), "both unpinned: both play shared")
        #expect(!store.isSlotChange(from: nil, to: Self.speakers))
        #expect(store.isSlotChange(from: Self.speakers, to: Self.pods))
        #expect(store.isSlotChange(from: Self.pods, to: nil))
        let secondPair = EQOutputKey(uid: "B8-00:output", modelUID: Self.pods.modelUID, name: "AirPods Pro")
        #expect(!store.isSlotChange(from: Self.pods, to: secondPair), "the model fallback plays the same pin")
    }
}
