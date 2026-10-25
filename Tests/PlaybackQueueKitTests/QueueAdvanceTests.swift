import PlaybackQueueKit
import Testing

// MARK: - QueueAdvance decision core (S9-Q1) — the REAL logic, tested directly

//
// These import the shipped `PlaybackQueueKit` target, so a regression in
// `nextIndex`/`previousIndex` is caught against the code that actually ships (the view
// model's use of it: `AutoAdvanceTests` and `ManualSkipTests` in AdaptiveSoundTests).
// The queue's own order only: shuffle is `ShufflePass` (`ShufflePassTests`).

@Suite("PlaybackQueueKit — QueueAdvance decision core (VM-QA)")
struct QueueAdvanceTests {
    @Test("VM-QA-01: linear advance steps to current+1 mid-queue")
    func linearStep() {
        #expect(QueueAdvance.nextIndex(current: 0, count: 3, repeatMode: 0) == 1)
        #expect(QueueAdvance.nextIndex(current: 1, count: 3, repeatMode: 0) == 2)
    }

    @Test("VM-QA-02: last track, no-repeat → nil (stop)")
    func lastNoRepeatStops() {
        #expect(QueueAdvance.nextIndex(current: 2, count: 3, repeatMode: 0) == nil)
    }

    @Test("VM-QA-03: last track, repeat-all → wraps to 0")
    func lastRepeatAllWraps() {
        #expect(QueueAdvance.nextIndex(current: 2, count: 3, repeatMode: 1) == 0)
    }

    @Test("VM-QA-04: repeat-one auto-repeats current; manual Next steps forward")
    func repeatOneAutoVsManual() {
        #expect(QueueAdvance.nextIndex(current: 1, count: 3, repeatMode: 2) == 1)
        #expect(QueueAdvance.nextIndex(current: 1, count: 3, repeatMode: 2, manualSkip: true) == 2)
    }

    @Test("VM-QA-05: empty queue → nil (next and previous)")
    func emptyQueue() {
        #expect(QueueAdvance.nextIndex(current: 0, count: 0, repeatMode: 1) == nil)
        #expect(QueueAdvance.previousIndex(current: 0, count: 0, repeatMode: 1) == nil)
    }

    @Test("VM-QA-06: previous steps back; first-track no-repeat → nil; repeat-all wraps to last")
    func previousBehaviour() {
        #expect(QueueAdvance.previousIndex(current: 2, count: 3, repeatMode: 0) == 1)
        #expect(QueueAdvance.previousIndex(current: 0, count: 3, repeatMode: 0) == nil)
        #expect(QueueAdvance.previousIndex(current: 0, count: 3, repeatMode: 1) == 2)
    }
}
