import PlaybackQueueKit
import Testing

// MARK: - ResumePoint — where a paused song resumes, owned by its queue slot (VM-RP)

//
// Imports the shipped `PlaybackQueueKit` target, so the rule the view model runs (`pause()`, `play()`,
// a scrub while paused, the `selectedTrackIndex` didSet, `pausedResumePosition`) is the rule under
// test. A slot id is a UUID in the app; here a queue is a list of Int slot ids, and "the selected slot"
// is the id at the selected row — exactly how `selectedSlotID` reads it.

@Suite("PlaybackQueueKit — ResumePoint, the paused place (VM-RP)")
struct ResumePointTests {
    /// The selected slot of `queue` at `row` (nil out of range), as `AudioViewModel.selectedSlotID`.
    private static func slot(_ queue: [Int], _ row: Int?) -> Int? {
        row.flatMap { $0 >= 0 && $0 < queue.count ? queue[$0] : nil }
    }

    @Test("VM-RP-01: the place resumes its own slot, and no other")
    func belongsToItsSlot() {
        let point = ResumePoint(slot: 7, seconds: 90)
        #expect(point.seconds(resuming: 7) == 90)
        #expect(point.seconds(resuming: 8) == nil)
        #expect(point.seconds(resuming: nil) == nil)
    }

    @Test("VM-RP-02: removing a row ABOVE the paused song shifts its row and keeps its place")
    func removeAboveKeepsThePlace() {
        var queue = [10, 11, 12]
        let point = ResumePoint(slot: 12, seconds: 90) // paused on row 2
        queue.remove(at: 0) // the view model re-anchors the row: 2 → 1
        #expect(point.seconds(resuming: Self.slot(queue, 1)) == 90)
    }

    @Test("VM-RP-03: moving rows across the paused song keeps its place (the row follows the slot)")
    func reorderKeepsThePlace() {
        var queue = [10, 11, 12]
        let point = ResumePoint(slot: 12, seconds: 90)
        queue.append(queue.removeFirst()) // row 0 dragged to the end: [11, 12, 10], the paused song now row 1
        let row = queue.firstIndex(of: 12)
        #expect(row == 1)
        #expect(point.seconds(resuming: Self.slot(queue, row)) == 90)
    }

    @Test("VM-RP-04: removing the paused song leaves nothing to resume in the row it slides into")
    func removingThePausedSongDropsThePlace() {
        var queue = [10, 11, 12]
        let point = ResumePoint(slot: 11, seconds: 90) // paused on row 1
        queue.remove(at: 1) // row 1 now holds slot 12 — the same ROW, another song
        #expect(point.seconds(resuming: Self.slot(queue, 1)) == nil)
        // The last row removed: the selection steps back to another slot, still nothing to resume.
        var tail = [10, 11]
        let last = ResumePoint(slot: 11, seconds: 30)
        tail.remove(at: 1)
        #expect(last.seconds(resuming: Self.slot(tail, 0)) == nil)
    }

    @Test("VM-RP-05: the same song queued twice — the place belongs to the slot paused, not the song")
    func duplicateSongsAreDistinctSlots() {
        // Slots 20 and 21 hold the same file; the user paused the copy in slot 21.
        let point = ResumePoint(slot: 21, seconds: 45)
        #expect(point.seconds(resuming: 20) == nil)
        #expect(point.seconds(resuming: 21) == 45)
    }

    @Test("VM-RP-06: a scrub while paused moves where Play resumes, for the same slot only")
    func scrubMovesThePlace() {
        var point = ResumePoint(slot: 3, seconds: 90)
        point.move(to: 30)
        #expect(point.seconds(resuming: 3) == 30)
        point.move(to: 0) // scrubbed to the very start: still paused (resume at 0), not stopped
        #expect(point.seconds(resuming: 3) == 0)
        #expect(point.seconds(resuming: 4) == nil)
    }
}
