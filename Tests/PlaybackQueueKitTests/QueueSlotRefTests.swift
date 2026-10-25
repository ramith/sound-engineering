import Foundation
import PlaybackQueueKit
import Testing

// MARK: - QueueSlotRef — how a persisted queue slot names what it plays (R1.1-B, seam S5) (VM-QSR)

//
// The encoded form is stored with the queue, so these tests pin it: a rename of a case or a label
// would make every saved queue unreadable after an upgrade.

@Suite("PlaybackQueueKit — QueueSlotRef, the persisted slot's identity (VM-QSR)")
struct QueueSlotRefTests {
    @Test("VM-QSR-01: a library track and a loose file round-trip through the stored form")
    func roundTrips() throws {
        let slots: [QueueSlotRef] = [.track(id: 42), .loose(path: "/Volumes/T7/Album/01 – Song.flac")]
        let data = try JSONEncoder().encode(slots)
        #expect(try JSONDecoder().decode([QueueSlotRef].self, from: data) == slots)
    }

    @Test("VM-QSR-02: the stored form is frozen — a queue saved by an earlier build still decodes")
    func storedFormIsFrozen() throws {
        let saved = Data(#"[{"track":{"id":42}},{"loose":{"path":"\/Volumes\/T7\/a.flac"}}]"#.utf8)
        #expect(try JSONDecoder().decode([QueueSlotRef].self, from: saved) == [
            .track(id: 42), .loose(path: "/Volumes/T7/a.flac"),
        ])
    }

    @Test("VM-QSR-03: a track and a loose file are never equal, even when they play the same file")
    func kindsAreDistinct() {
        #expect(QueueSlotRef.track(id: 1) != .loose(path: "1"))
        #expect(Set<QueueSlotRef>([.track(id: 1), .track(id: 1), .loose(path: "/a")]).count == 2)
    }
}
