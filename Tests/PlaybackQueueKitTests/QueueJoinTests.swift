import PlaybackQueueKit
import Testing

// MARK: - The launch's join: what was queued before the restore meets the restored queue (R1.1-B, M2) (VM-QJ)

//
// The shipped `QueueResumeRecord.Resolved.joined`: a stored record resolved to slots, joined by a queue made
// before the restore. Each case names where an open AFTER the restore puts the same files (`playTrackNextNow`
// = `QueueInsert.playNextNow`, then Play Next). The view model's wiring — both orders compared on the real
// view model and a real store, shuffle on and off — is VM-QS-12 in AdaptiveSoundTests.

/// A queue slot: its identity, and the file it plays.
private struct Slot: Identifiable, Equatable {
    let id: String
    let file: String
}

/// Slots named by their files, the identity `prefix` + file: "r" for the restored queue, "b" for before it.
private func slots(_ files: [String], _ prefix: String) -> [Slot] {
    files.map { Slot(id: prefix + $0, file: $0) }
}

@Suite("PlaybackQueueKit — the launch's join (VM-QJ)")
struct QueueJoinTests {
    /// The record of the queue `files`, `cursor` selected, `shuffle` its pass over the files' rows.
    private func restored(_ files: [String], cursor: Int?, shuffle: ShufflePass<Int>? = nil) throws
        -> QueueResumeRecord.Resolved<Slot> {
        let refs = files.indices.map { QueueSlotRef.track(id: Int64($0)) }
        let record = try #require(QueueResumeRecord(slots: refs, cursor: cursor, offset: 30, shuffle: shuffle))
        return record.resolved { ref in
            guard case let .track(id) = ref else { return nil }
            return Slot(id: "r" + files[Int(id)], file: files[Int(id)])
        }
    }

    private func join(_ restored: QueueResumeRecord.Resolved<Slot>, _ before: [Slot], started: Int?,
                      shuffled: Bool = false) -> QueueJoined<Slot> {
        restored.joined(by: before, started: started, shuffled: shuffled) { $0.file == $1.file }
    }

    @Test("VM-QJ-01: the song started goes right after the restored song, the rest after it, in order")
    func afterTheRestoredSong() throws {
        let joined = try join(restored(["a", "b", "c", "d"], cursor: 1), slots(["x", "y"], "b"), started: 0)
        #expect(joined.items.map(\.id) == ["ra", "rb", "bx", "by", "rc", "rd"] && joined.selected == 2)
    }

    @Test("VM-QJ-02 (BI-P03): a file the restored queue holds is moved there, never doubled")
    func aHeldFileMoves() throws {
        let later = try join(restored(["a", "b", "c"], cursor: 0), slots(["c"], "b"), started: 0)
        #expect(later.items.map(\.id) == ["ra", "bc", "rb"] && later.selected == 1)
        let earlier = try join(restored(["a", "b", "c", "d"], cursor: 2), slots(["a"], "b"), started: 0)
        #expect(earlier.items.map(\.id) == ["rb", "rc", "ba", "rd"] && earlier.selected == 2)
        // The rest of an open is Play Next after the song started: a held file there is queued again.
        let rest = try join(restored(["a", "b", "c"], cursor: 0), slots(["x", "c"], "b"), started: 0)
        #expect(rest.items.map(\.file) == ["a", "x", "c", "b", "c"])
    }

    @Test("VM-QJ-03 (BI-P03b): nothing selected in the restored queue — the song started goes first")
    func nothingSelectedGoesFirst() throws {
        let joined = try join(restored(["a", "b"], cursor: nil), slots(["c"], "b"), started: 0)
        #expect(joined.items.map(\.id) == ["bc", "ra", "rb"] && joined.selected == 0 && joined.pass == nil)
        let held = try join(restored(["a", "b"], cursor: nil), slots(["b"], "b"), started: 0)
        #expect(held.items.map(\.id) == ["bb", "ra"] && held.selected == 0)
    }

    @Test("VM-QJ-04: the restored song itself, started — it plays in its own place")
    func theRestoredSongItself() throws {
        let joined = try join(restored(["a", "b", "c"], cursor: 1), slots(["b", "x"], "b"), started: 0)
        #expect(joined.items.map(\.id) == ["ra", "bb", "bx", "rc"] && joined.selected == 1)
    }

    @Test("VM-QJ-05: nothing started (an Add to Queue) — at the end; the restored song stays selected")
    func nothingStartedGoesAtTheEnd() throws {
        let joined = try join(restored(["a", "b", "c"], cursor: 1), slots(["x"], "b"), started: nil)
        #expect(joined.items.map(\.id) == ["ra", "rb", "rc", "bx"] && joined.selected == 1)
    }

    @Test("VM-QJ-06: under shuffle the restored pass goes on — what joined plays now, then the pass as it was")
    func theRestoredPassGoesOn() throws {
        var kept = ShufflePass(beginningAt: 2, among: Array(0 ..< 6), seed: 0x16)
        try kept.arrive(at: #require(kept.peekNext(repeatMode: 0)))
        let files = ["a", "b", "c", "d", "e", "f"]
        let cursor = try #require(kept.current)
        let joined = try join(restored(files, cursor: cursor, shuffle: kept), slots(["x", "y"], "b"), started: 0,
                              shuffled: true)
        var pass = try #require(joined.pass)
        let selected = try #require(joined.selected)
        #expect(pass.current == "bx" && joined.items[selected].id == "bx")
        #expect(pass.previous(repeatMode: 0) == "r" + files[cursor], "the restored song is not the one before")
        #expect(pass.peekNext(repeatMode: 0) == "by")
        pass.arrive(at: "by")
        let ahead = kept.permutation[(kept.position + 1)...].map { "r" + files[$0] }
        #expect(Array(pass.permutation[(pass.position + 1)...]) == ahead, "the restored pass does not go on")
        #expect(pass.seed == kept.seed, "the join drew from the pass's randomness")
        // Shuffle off now: no pass, whatever the record kept.
        #expect(try join(restored(files, cursor: cursor, shuffle: kept), slots(["x"], "b"), started: 0).pass == nil)
    }

    @Test("VM-QJ-07: under shuffle, songs before the one started count as played; a moved song leaves the pass")
    func shuffleWithAStartedSongLater() throws {
        let kept = ShufflePass(beginningAt: 0, among: Array(0 ..< 4), seed: 0x17)
        let files = ["a", "b", "c", "d"]
        // Two opens before the restore: x (then y queued), then c — which the restored queue holds.
        let joined = try join(restored(files, cursor: 0, shuffle: kept), slots(["x", "c", "y"], "b"), started: 1,
                              shuffled: true)
        #expect(joined.items.map(\.id) == ["ra", "bx", "bc", "by", "rb", "rd"] && joined.selected == 2)
        let pass = try #require(joined.pass)
        #expect(pass.current == "bc" && pass.previous(repeatMode: 0) == "bx" && pass.peekNext(repeatMode: 0) == "by")
        #expect(!(pass.permutation + pass.history).contains("rc") && Set(pass.permutation).count == 6)
    }
}
