import PlaybackQueueKit
import Testing

// MARK: - PlaybackOrder — a shuffle / repeat change mid-song applies to THIS song's end (VM-PO)

//
// Imports the shipped `PlaybackQueueKit` target, so the rule `AudioViewModel.toggleShuffle` /
// `cycleRepeatMode` re-arm the on-deck by is the rule under test. The shuffle picker is injected:
// `pick` is a deterministic stand-in, and `noPick` fails the test if a pick that must stand re-rolls.

@Suite("PlaybackQueueKit — PlaybackOrder, re-arming the on-deck after a mode change (VM-PO)")
struct PlaybackOrderTests {
    private static let off = PlaybackOrder(shuffle: false, repeatMode: 0)
    private static let all = PlaybackOrder(shuffle: false, repeatMode: 1)
    private static let one = PlaybackOrder(shuffle: false, repeatMode: 2)
    private static let shuffleOff = PlaybackOrder(shuffle: true, repeatMode: 0)
    private static let shuffleAll = PlaybackOrder(shuffle: true, repeatMode: 1)
    private static let shuffleOne = PlaybackOrder(shuffle: true, repeatMode: 2)

    /// The deterministic shuffle stand-in shared with the other queue suites.
    private let pick = deterministicPick

    /// A picker that records its calls, and picks the song BEFORE `current` — never the song in order,
    /// so a pick it made is told apart from a pick kept.
    private final class PickRecorder {
        var calls = 0
        func pick(_ current: Int, _ count: Int) -> Int {
            calls += 1
            return (current + count - 1) % count
        }
    }

    @Test("VM-PO-01: Repeat One turned on mid-song arms THIS song (G-RPT-1)")
    func repeatOneOnArmsTheSongItself() {
        // Linear, playing 0 of 3, track 1 armed.
        #expect(Self.one.onDeck(switchingFrom: Self.all, current: 0, count: 3, armed: 1, randomPick: pick) == 0)
        // Under shuffle too: the shuffle pick gives way to the song itself.
        #expect(Self.shuffleOne.onDeck(switchingFrom: Self.shuffleAll, current: 2, count: 5, armed: 4,
                                       randomPick: pick) == 2)
    }

    @Test("VM-PO-02: Repeat All turned on during the LAST song wraps to the first (G-RPT-2)")
    func repeatAllOnTheLastSongWraps() {
        #expect(Self.all.onDeck(switchingFrom: Self.off, current: 2, count: 3, armed: nil, randomPick: pick) == 0)
    }

    @Test("VM-PO-03: Repeat turned off after One moves on — in order, or by a fresh shuffle pick (G-RPT-3)")
    func leavingRepeatOneMovesOn() {
        #expect(Self.off.onDeck(switchingFrom: Self.one, current: 0, count: 3, armed: 0, randomPick: pick) == 1)
        // The last song with Repeat off: nothing follows.
        #expect(Self.off.onDeck(switchingFrom: Self.one, current: 2, count: 3, armed: 2, randomPick: pick) == nil)
        // Under shuffle the armed "pick" was the song itself, so it is re-picked (never the song again).
        let next = Self.shuffleOff.onDeck(switchingFrom: Self.shuffleOne, current: 2, count: 5, armed: 2,
                                          randomPick: pick)
        #expect(next != nil && next != 2)
    }

    @Test("VM-PO-04: Repeat off during the last song (from All) ends the queue after it")
    func repeatOffOnTheLastSongEnds() {
        #expect(Self.off.onDeck(switchingFrom: Self.all, current: 2, count: 3, armed: 0, randomPick: pick) == nil)
    }

    @Test("VM-PO-05: shuffle turned on mid-song picks at random instead of the song in order")
    func shuffleOnPicks() {
        let recorder = PickRecorder()
        let next = Self.shuffleOff.onDeck(switchingFrom: Self.off, current: 1, count: 4, armed: 2,
                                          randomPick: recorder.pick)
        #expect(recorder.calls == 1)
        #expect(next == 0) // the picker's pick, not the in-order song that was armed
    }

    @Test("VM-PO-06: shuffle turned off mid-song goes on in order")
    func shuffleOffGoesInOrder() {
        #expect(Self.off.onDeck(switchingFrom: Self.shuffleOff, current: 1, count: 4, armed: 3, randomPick: pick) == 2)
        // The last song, shuffle off with Repeat off: nothing follows.
        #expect(Self.off.onDeck(switchingFrom: Self.shuffleOff, current: 3, count: 4, armed: 0,
                                randomPick: pick) == nil)
    }

    @Test("VM-PO-07: repeat all/off toggled under shuffle keeps the armed pick — no re-roll")
    func repeatUnderShuffleKeepsThePick() {
        let recorder = PickRecorder()
        #expect(Self.shuffleAll.onDeck(switchingFrom: Self.shuffleOff, current: 1, count: 5, armed: 4,
                                       randomPick: recorder.pick) == 4)
        #expect(Self.shuffleOff.onDeck(switchingFrom: Self.shuffleAll, current: 1, count: 5, armed: 4,
                                       randomPick: recorder.pick) == 4)
        #expect(recorder.calls == 0)
    }

    @Test("VM-PO-08: under shuffle with nothing armed, a pick is made")
    func shuffleWithNothingArmedPicks() {
        #expect(Self.shuffleAll.onDeck(switchingFrom: Self.shuffleOff, current: 1, count: 5, armed: nil,
                                       randomPick: pick) != nil)
    }

    @Test("VM-PO-09: a one-song queue — Repeat All arms the song itself, Repeat off arms nothing")
    func singleSongQueue() {
        #expect(Self.all.onDeck(switchingFrom: Self.off, current: 0, count: 1, armed: nil, randomPick: pick) == 0)
        #expect(Self.off.onDeck(switchingFrom: Self.one, current: 0, count: 1, armed: 0, randomPick: pick) == nil)
    }

    @Test("VM-PO-10: an empty queue arms nothing, whatever the order")
    func emptyQueue() {
        #expect(Self.one.onDeck(switchingFrom: Self.off, current: 0, count: 0, armed: nil, randomPick: pick) == nil)
        #expect(Self.shuffleAll.onDeck(switchingFrom: Self.off, current: 0, count: 0, armed: nil,
                                       randomPick: pick) == nil)
    }

    // MARK: After a queue edit (council C-17) — `current` and `armed` are rows in the EDITED queue

    @Test("VM-PO-11: in order, next is the row now under the playing one — a drag in, or the next dragged away")
    func inOrderNextFollowsTheEdit() {
        // [t0*, t3, t1, t2, …]: t3 dragged in under the playing t0; t1, the armed pick, is now row 2.
        #expect(Self.off.onDeck(afterEditing: 0, count: 6, armed: 2, randomPick: pick) == 1)
        // [t0*, t2, …, t1]: the armed t1 dragged to the bottom.
        #expect(Self.all.onDeck(afterEditing: 0, count: 6, armed: 5, randomPick: pick) == 1)
        // Unchanged when the edit did not move what is under the playing song.
        #expect(Self.off.onDeck(afterEditing: 1, count: 6, armed: 2, randomPick: pick) == 2)
    }

    @Test("VM-PO-12: an append to the last song plays next — under Repeat All too, not a whole cycle later")
    func appendToTheLastSong() {
        #expect(Self.off.onDeck(afterEditing: 2, count: 4, armed: nil, randomPick: pick) == 3)
        #expect(Self.all.onDeck(afterEditing: 2, count: 4, armed: 0, randomPick: pick) == 3)
        // The removal of the only next song on the last-but-one row: Repeat off ends after the current.
        #expect(Self.off.onDeck(afterEditing: 2, count: 3, armed: nil, randomPick: pick) == nil)
    }

    @Test("VM-PO-13: a shuffle pick stands through an edit — never re-rolled")
    func aShufflePickStands() {
        let recorder = PickRecorder()
        #expect(Self.shuffleOff.onDeck(afterEditing: 1, count: 6, armed: 4, randomPick: recorder.pick) == 4)
        #expect(Self.shuffleAll.onDeck(afterEditing: 1, count: 6, armed: 0, randomPick: recorder.pick) == 0)
        #expect(recorder.calls == 0)
    }

    @Test("VM-PO-14: a one-song shuffle that grew picks the new song; a removed shuffle pick is picked again")
    func shuffleWithNothingArmedPicksAgain() {
        let recorder = PickRecorder()
        #expect(Self.shuffleOff.onDeck(afterEditing: 0, count: 2, armed: nil, randomPick: recorder.pick) == 1)
        #expect(recorder.calls == 1)
        #expect(Self.shuffleAll.onDeck(afterEditing: 2, count: 5, armed: nil, randomPick: pick) != nil)
    }

    @Test("VM-PO-15: under Repeat One the armed pick stands — this song, or a Play Next over it")
    func repeatOneKeepsItsPick() {
        #expect(Self.one.onDeck(afterEditing: 3, count: 6, armed: 3, randomPick: pick) == 3)
        #expect(Self.one.onDeck(afterEditing: 3, count: 6, armed: 4, randomPick: pick) == 4) // Play Next
        #expect(Self.shuffleOne.onDeck(afterEditing: 3, count: 6, armed: 1, randomPick: pick) == 1)
        // Nothing armed (the Play Next song was removed): this song again.
        #expect(Self.one.onDeck(afterEditing: 3, count: 5, armed: nil, randomPick: pick) == 3)
    }
}
