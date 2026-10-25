import PlaybackQueueKit
import Testing

// MARK: - PlaybackOrder — what plays next and before, and what a mid-song change or edit arms (VM-PO)

//
// Imports the shipped `PlaybackQueueKit` target, so the rule `AudioViewModel` computes Next, Previous and
// its on-deck pick by is the rule under test. Under shuffle the pick is the `ShufflePass`'s (R1.1-B, council
// C-16): its slots here are the queue's rows, so `row` is the identity.

@Suite("PlaybackQueueKit — PlaybackOrder, next, previous and the on-deck after a change (VM-PO)")
struct PlaybackOrderTests {
    private static let off = PlaybackOrder(shuffle: false, repeatMode: 0)
    private static let all = PlaybackOrder(shuffle: false, repeatMode: 1)
    private static let one = PlaybackOrder(shuffle: false, repeatMode: 2)
    private static let shuffleOff = PlaybackOrder(shuffle: true, repeatMode: 0)
    private static let shuffleAll = PlaybackOrder(shuffle: true, repeatMode: 1)
    private static let shuffleOne = PlaybackOrder(shuffle: true, repeatMode: 2)

    /// No pass: the queue's own order.
    private static let inOrder: ShufflePass<Int>? = nil

    /// A pass over `count` rows beginning at `current`, and `played` songs on into it.
    private static func pass(_ count: Int, at current: Int, played: Int = 0,
                             seed: UInt64 = 0x0D3C) -> ShufflePass<Int> {
        var pass = ShufflePass(beginningAt: current, among: Array(0 ..< count), seed: seed)
        for _ in 0 ..< played {
            guard let next = pass.peekNext(repeatMode: 0) else { break }
            pass.arrive(at: next)
        }
        return pass
    }

    private static func row(_ slot: Int) -> Int? {
        slot
    }

    @Test("VM-PO-01: Repeat One turned on mid-song arms THIS song (G-RPT-1)")
    func repeatOneOnArmsTheSongItself() {
        #expect(Self.one.next(after: 0, count: 3, pass: Self.inOrder, row: Self.row) == 0)
        // Under shuffle too: the pass's pick gives way to the song itself.
        #expect(Self.shuffleOne.next(after: 2, count: 5, pass: Self.pass(5, at: 2), row: Self.row) == 2)
    }

    @Test("VM-PO-02: Repeat All turned on during the LAST song wraps to the first (G-RPT-2)")
    func repeatAllOnTheLastSongWraps() {
        #expect(Self.all.next(after: 2, count: 3, pass: Self.inOrder, row: Self.row) == 0)
    }

    @Test("VM-PO-03: leaving Repeat One moves on — in order, or to the pass's next song (G-RPT-3)")
    func leavingRepeatOneMovesOn() {
        #expect(Self.off.next(after: 0, count: 3, pass: Self.inOrder, row: Self.row) == 1)
        #expect(Self.off.next(after: 2, count: 3, pass: Self.inOrder, row: Self.row) == nil)
        let pass = Self.pass(5, at: 2)
        let next = Self.shuffleOff.next(after: 2, count: 5, pass: pass, row: Self.row)
        #expect(next == pass.permutation[1] && next != 2)
    }

    @Test("VM-PO-04 (KI-PB-03): Repeat off on the last song ends the queue — in order, and at a pass's end")
    func repeatOffOnTheLastSongEnds() {
        #expect(Self.off.next(after: 2, count: 3, pass: Self.inOrder, row: Self.row) == nil)
        let last = Self.pass(4, at: 1, played: 3)
        #expect(Self.shuffleOff.next(after: 0, count: 4, pass: last, row: Self.row) == nil,
                "shuffle with Repeat off never ended (KI-PB-03)")
        // Repeat All there arms the next pass's first song — never the song that just ended.
        let wrapped = Self.shuffleAll.next(after: 0, count: 4, pass: last, row: Self.row)
        #expect(wrapped != nil && wrapped != last.current)
    }

    @Test("VM-PO-05: shuffle turned on mid-song arms the pass's next song instead of the song in order")
    func shuffleOnArmsThePassNext() {
        let pass = Self.pass(6, at: 1, seed: 21)
        #expect(Self.shuffleOff.next(after: 1, count: 6, pass: pass, row: Self.row) == pass.permutation[1])
    }

    @Test("VM-PO-06: shuffle turned off mid-song goes on in order")
    func shuffleOffGoesInOrder() {
        #expect(Self.off.next(after: 1, count: 4, pass: Self.inOrder, row: Self.row) == 2)
        #expect(Self.off.next(after: 3, count: 4, pass: Self.inOrder, row: Self.row) == nil)
    }

    @Test("VM-PO-07: repeat all/off toggled mid-pass keeps the pass's pick — no re-roll")
    func repeatUnderShuffleKeepsThePick() {
        let pass = Self.pass(5, at: 1, played: 1)
        let pick = Self.shuffleAll.next(after: 1, count: 5, pass: pass, row: Self.row)
        #expect(pick != nil)
        #expect(Self.shuffleOff.next(after: 1, count: 5, pass: pass, row: Self.row) == pick)
    }

    @Test("VM-PO-08: a manual Next under Repeat One steps on — at the pass's end only with Repeat All")
    func manualNextUnderRepeatOne() {
        let pass = Self.pass(4, at: 0, played: 1)
        #expect(Self.shuffleOne.next(after: 0, count: 4, manualSkip: true, pass: pass, row: Self.row)
            == pass.permutation[2])
        let last = Self.pass(4, at: 0, played: 3)
        #expect(Self.shuffleOne.next(after: 0, count: 4, manualSkip: true, pass: last, row: Self.row) == nil)
        #expect(Self.one.next(after: 1, count: 3, manualSkip: true, pass: Self.inOrder, row: Self.row) == 2)
    }

    @Test("VM-PO-09: a one-song queue — Repeat All arms the song itself, Repeat off arms nothing")
    func singleSongQueue() {
        #expect(Self.all.next(after: 0, count: 1, pass: Self.inOrder, row: Self.row) == 0)
        #expect(Self.off.next(after: 0, count: 1, pass: Self.inOrder, row: Self.row) == nil)
        #expect(Self.shuffleAll.next(after: 0, count: 1, pass: Self.pass(1, at: 0), row: Self.row) == 0)
        #expect(Self.shuffleOff.next(after: 0, count: 1, pass: Self.pass(1, at: 0), row: Self.row) == nil)
    }

    @Test("VM-PO-10: an empty queue arms nothing, whatever the order")
    func emptyQueue() {
        #expect(Self.one.next(after: 0, count: 0, pass: Self.inOrder, row: Self.row) == nil)
        #expect(Self.shuffleAll.next(after: 0, count: 0, pass: Self.inOrder, row: Self.row) == nil)
        #expect(Self.shuffleAll.previous(before: 0, count: 0, pass: Self.inOrder, row: Self.row) == nil)
    }

    // MARK: After a queue edit (council C-17) — `current` and `armed` are rows in the EDITED queue

    @Test("VM-PO-11: in order, next is the row now under the playing one — a drag in, or the next dragged away")
    func inOrderNextFollowsTheEdit() {
        // [t0*, t3, t1, t2, …]: t3 dragged in under the playing t0; t1, the armed pick, is now row 2.
        #expect(Self.off.onDeck(afterEditing: 0, count: 6, armed: 2, pass: Self.inOrder, row: Self.row) == 1)
        // [t0*, t2, …, t1]: the armed t1 dragged to the bottom.
        #expect(Self.all.onDeck(afterEditing: 0, count: 6, armed: 5, pass: Self.inOrder, row: Self.row) == 1)
        // Unchanged when the edit did not move what is under the playing song.
        #expect(Self.off.onDeck(afterEditing: 1, count: 6, armed: 2, pass: Self.inOrder, row: Self.row) == 2)
    }

    @Test("VM-PO-12: an append to the last song plays next — under Repeat All too, not a whole cycle later")
    func appendToTheLastSong() {
        #expect(Self.off.onDeck(afterEditing: 2, count: 4, armed: nil, pass: Self.inOrder, row: Self.row) == 3)
        #expect(Self.all.onDeck(afterEditing: 2, count: 4, armed: 0, pass: Self.inOrder, row: Self.row) == 3)
        // The removal of the only next song on the last-but-one row: Repeat off ends after the current.
        #expect(Self.off.onDeck(afterEditing: 2, count: 3, armed: nil, pass: Self.inOrder, row: Self.row) == nil)
        // At a pass's last song, an append plays next, under Repeat All too.
        var last = Self.pass(3, at: 0, played: 2)
        last.follow([0, 1, 2, 3])
        #expect(Self.shuffleAll.onDeck(afterEditing: 0, count: 4, armed: nil, pass: last, row: Self.row) == 3)
    }

    @Test("VM-PO-13: the pass's pick stands through an edit — never re-rolled")
    func aShufflePickStands() {
        var pass = Self.pass(6, at: 1, played: 1)
        let armed = pass.peekNext(repeatMode: 0)
        pass.follow([0, 1, 2, 3, 4, 5, 6])
        #expect(Self.shuffleOff.onDeck(afterEditing: 1, count: 7, armed: armed, pass: pass, row: Self.row) == armed)
    }

    @Test("VM-PO-14: a one-song shuffle that grew plays the new song; a removed pick gives way to the pass's next")
    func shuffleAfterGrowthOrRemoval() {
        var single = Self.pass(1, at: 0)
        single.follow([0, 1])
        #expect(Self.shuffleOff.onDeck(afterEditing: 0, count: 2, armed: nil, pass: single, row: Self.row) == 1)
        var pass = Self.pass(5, at: 2)
        let armed = pass.permutation[1]
        let after = pass.permutation[2]
        pass.follow([0, 1, 2, 3, 4].filter { $0 != armed })
        #expect(pass.peekNext(repeatMode: 0) == after)
    }

    @Test("VM-PO-15: under Repeat One the armed pick stands — this song, or a Play Next over it")
    func repeatOneKeepsItsPick() {
        #expect(Self.one.onDeck(afterEditing: 3, count: 6, armed: 3, pass: Self.inOrder, row: Self.row) == 3)
        #expect(Self.one.onDeck(afterEditing: 3, count: 6, armed: 4, pass: Self.inOrder, row: Self.row) == 4)
        #expect(Self.shuffleOne.onDeck(afterEditing: 3, count: 6, armed: 1, pass: Self.pass(6, at: 3), row: Self.row)
            == 1)
        // Nothing armed (the Play Next song was removed): this song again.
        #expect(Self.one.onDeck(afterEditing: 3, count: 5, armed: nil, pass: Self.inOrder, row: Self.row) == 3)
    }

    @Test("VM-PO-16: Previous under shuffle walks the pass; at its first song a restart, or the last pass (All)")
    func previousUnderShuffle() {
        let pass = Self.pass(5, at: 2, played: 2)
        #expect(Self.shuffleOff.previous(before: 0, count: 5, pass: pass, row: Self.row) == pass.permutation[1])
        let fresh = Self.pass(5, at: 2)
        #expect(Self.shuffleOff.previous(before: 2, count: 5, pass: fresh, row: Self.row) == 2, "a restart")
        var second = Self.pass(3, at: 0, played: 2)
        let ended = second.current
        second.arrive(at: second.peekNext(repeatMode: 1) ?? 0)
        #expect(Self.shuffleAll.previous(before: 0, count: 3, pass: second, row: Self.row) == ended)
        #expect(Self.shuffleOff.previous(before: 0, count: 3, pass: second, row: Self.row) == second.current)
        // In order: back one row, Repeat All wrapping, else nothing at the first.
        #expect(Self.off.previous(before: 0, count: 3, pass: Self.inOrder, row: Self.row) == nil)
        #expect(Self.all.previous(before: 0, count: 3, pass: Self.inOrder, row: Self.row) == 2)
    }
}
