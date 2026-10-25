import Foundation
import PlaybackQueueKit
import Testing

// MARK: - QueueResumeRecord — what a crash or a quit leaves to come back to (R1.1-B; C-65, KI-PB-21) (VM-RR)

//
// The shipped record: built from a live queue, stored as text beside its offset, read back, and resolved
// tolerantly. The store's half (one transaction, one writer) is `ChecksQueueState` in VerifyLibraryStore;
// the view model's (the writer, the cadence, the restore) is `QueueRestoreTests` in AdaptiveSoundTests.

/// A queue slot as the app has one: its identity and what it plays.
private struct Slot {
    let id: String
    let ref: QueueSlotRef
}

@Suite("PlaybackQueueKit — QueueResumeRecord, the crash-restore record (VM-RR)")
struct QueueResumeRecordTests {
    private let queue = [
        Slot(id: "a", ref: .track(id: 10)), Slot(id: "b", ref: .loose(path: "/Volumes/T7/b.flac")),
        Slot(id: "c", ref: .track(id: 30)), Slot(id: "d", ref: .track(id: 40)),
    ]

    private func record(selected: String?, offset: Double, shuffle: ShufflePass<String>?) throws -> QueueResumeRecord {
        let made = QueueResumeRecord(queue: queue, id: \.id, ref: \.ref, selected: selected, offset: offset,
                                     shuffle: shuffle)
        return try #require(made)
    }

    @Test("VM-RR-01: a live queue with its shuffle pass is stored and read back as it was")
    func roundTrip() throws {
        var pass = ShufflePass(beginningAt: "b", among: queue.map(\.id), seed: 0xC65)
        try pass.arrive(at: #require(pass.peekNext(repeatMode: 0)))
        let made = try record(selected: pass.current, offset: 61.5, shuffle: pass)
        #expect(made.slots == queue.map(\.ref) && made.cursor == queue.firstIndex { $0.id == pass.current })
        #expect(made.shuffle?.permutation == pass.permutation.compactMap { id in queue.firstIndex { $0.id == id } })
        #expect(made.shuffle?.position == 1 && made.shuffle?.seed == pass.seed)
        let read = try QueueResumeRecord(storedQueue: made.encodedQueue(), offset: 61.5)
        #expect(read == made)
        // One queue is one text: the same record encodes the same, so the store compares texts.
        #expect(try made.encodedQueue() == read.encodedQueue())
    }

    @Test("VM-RR-02: the stored form is frozen — a record saved by this build still reads after an update")
    func storedFormIsFrozen() throws {
        let saved = #"{"cursor":1,"format":1,"shuffle":{"history":[],"permutation":[1,0,2],"position":0,"seed":7},"#
            + #""slots":[{"track":{"id":5}},{"loose":{"path":"\/x\/y.flac"}},{"track":{"id":6}}]}"#
        let read = try QueueResumeRecord(storedQueue: saved, offset: 3)
        #expect(read.slots == [.track(id: 5), .loose(path: "/x/y.flac"), .track(id: 6)])
        #expect(read.cursor == 1 && read.offset == 3 && read.shuffle?.permutation == [1, 0, 2])
        #expect(try read.encodedQueue() == saved)
    }

    @Test("VM-RR-03: a record that does not hold together, or a newer one, is refused — never half-read")
    func refusals() {
        let refused = [
            #"{"format":1,"slots":[{"track":{"id":5}}],"cursor":3}"#, // cursor past the slots
            #"{"format":1,"slots":[{"track":{"id":5}}],"cursor":0,"#
                + #""shuffle":{"history":[],"permutation":[0,1],"position":0,"seed":1}}"#, // pass slot past them
            #"{"format":1,"slots":[{"track":{"id":5}},{"track":{"id":6}}],"cursor":0,"#
                + #""shuffle":{"history":[],"permutation":[1,0],"position":0,"seed":1}}"#, // pass plays another
            #"{"format":2,"slots":[]}"#, // a newer build's
            #"{"format":1,"slots":[{"track":{"id":5}"#, // cut short
        ]
        for text in refused {
            #expect(throws: (any Error).self, "\(text)") { try QueueResumeRecord(storedQueue: text, offset: 0) }
        }
    }

    @Test("VM-RR-04: an offset is a place in the selected song — bad numbers, or nothing selected, read as 0")
    func offsets() throws {
        #expect(try record(selected: "a", offset: -.infinity, shuffle: nil).offset == 0)
        #expect(try record(selected: "a", offset: .nan, shuffle: nil).offset == 0)
        #expect(try record(selected: nil, offset: 12, shuffle: nil).offset == 0)
        let unknown = QueueResumeRecord(queue: queue, id: \.id, ref: \.ref, selected: "zz", offset: 1, shuffle: nil)
        #expect(unknown == nil, "a selected slot the queue does not have")
    }

    @Test("VM-RR-05: slots not found are dropped; the cursor, the offset and the pass follow their songs")
    func tolerantResolve() throws {
        let pass = ShufflePass(beginningAt: "d", among: queue.map(\.id), seed: 1)
        let made = try record(selected: "d", offset: 42, shuffle: pass)
        // Track 30 was deleted while the app was closed.
        let resolved = made.resolved { ref -> String? in ref == .track(id: 30) ? nil : "\(ref)" }
        #expect(resolved.items.count == 3 && resolved.cursor == 2 && resolved.offset == 42)
        let rows = try #require(resolved.shuffle)
        #expect(rows.current == 2 && Set(rows.permutation) == [0, 1, 2])
        // A loose file always comes back by its path, found or not: the dead-file badge says the rest.
        #expect(resolved.items.contains("\(QueueSlotRef.loose(path: "/Volumes/T7/b.flac"))"))
    }

    @Test("VM-RR-06: the selected song gone — in order the top of the queue, under shuffle the pass's next")
    func selectedSongGone() throws {
        let inOrder = try record(selected: "c", offset: 42, shuffle: nil)
            .resolved { ref -> QueueSlotRef? in ref == .track(id: 30) ? nil : ref }
        #expect(inOrder.cursor == nil && inOrder.offset == 0, "another song at the old offset")
        let pass = ShufflePass(beginningAt: "c", among: queue.map(\.id), seed: 9)
        let next = try #require(pass.peekNext(repeatMode: 0))
        let shuffled = try record(selected: "c", offset: 42, shuffle: pass)
            .resolved { ref -> QueueSlotRef? in ref == .track(id: 30) ? nil : ref }
        let nextRef = try #require(queue.first { $0.id == next }).ref
        #expect(shuffled.cursor.map { shuffled.items[$0] } == nextRef && shuffled.offset == 0)
        #expect(shuffled.shuffle?.current == shuffled.cursor)
    }

    @Test("VM-RR-07: a queue saved before the record (playlist + defaults' cursor) comes back tolerantly")
    func legacyCursor() {
        // The row still holds the song: that row.
        #expect(QueueResumeRecord.legacy(trackIDs: [1, 2, 3], cursorRow: 1, cursorTrackID: 2, offset: 9).cursor == 1)
        // The queue shifted: the song's first row.
        #expect(QueueResumeRecord.legacy(trackIDs: [2, 3, 2], cursorRow: 1, cursorTrackID: 2, offset: 9).cursor == 0)
        // The song is gone: none, and no offset.
        let gone = QueueResumeRecord.legacy(trackIDs: [1, 3], cursorRow: 1, cursorTrackID: 2, offset: 9)
        #expect(gone.cursor == nil && gone.offset == 0)
        // A cursor from before the id was kept: the row as it is, in range.
        #expect(QueueResumeRecord.legacy(trackIDs: [1, 3], cursorRow: 1, cursorTrackID: nil, offset: 9).cursor == 1)
        #expect(QueueResumeRecord.legacy(trackIDs: [1, 3], cursorRow: 5, cursorTrackID: nil, offset: 9).cursor == nil)
        #expect(QueueResumeRecord.legacy(trackIDs: [1, 3], cursorRow: nil, cursorTrackID: nil, offset: 9).offset == 0)
    }
}
