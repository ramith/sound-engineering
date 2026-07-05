import PlaybackQueueKit
import Testing

// MARK: - QueueAdvance decision core (S9-Q1) — the REAL logic, tested directly

//
// These import the shipped `PlaybackQueueKit` target (NOT the hand-mirror), so a
// regression in `nextIndex`/`previousIndex` is caught against the code that actually
// ships. Exact-value cases use a deterministic injected picker; the production
// `uniformRandomExcluding` is verified by property.

@Suite("PlaybackQueueKit — QueueAdvance decision core (VM-QA)")
struct QueueAdvanceTests {
    /// The shared deterministic shuffle stand-in (linear walk avoiding `current`) — one
    /// source of truth, reused by the mirror's state-machine tests too.
    let det = MockAdvanceController.deterministicPick

    @Test("VM-QA-01: linear advance steps to current+1 mid-queue")
    func linearStep() {
        #expect(QueueAdvance.nextIndex(current: 0, count: 3, shuffle: false, repeatMode: 0, randomPick: det) == 1)
        #expect(QueueAdvance.nextIndex(current: 1, count: 3, shuffle: false, repeatMode: 0, randomPick: det) == 2)
    }

    @Test("VM-QA-02: last track, no-repeat → nil (stop)")
    func lastNoRepeatStops() {
        #expect(QueueAdvance.nextIndex(current: 2, count: 3, shuffle: false, repeatMode: 0, randomPick: det) == nil)
    }

    @Test("VM-QA-03: last track, repeat-all → wraps to 0")
    func lastRepeatAllWraps() {
        #expect(QueueAdvance.nextIndex(current: 2, count: 3, shuffle: false, repeatMode: 1, randomPick: det) == 0)
    }

    @Test("VM-QA-04: repeat-one auto-repeats current; manual Next steps forward")
    func repeatOneAutoVsManual() {
        #expect(QueueAdvance.nextIndex(current: 1, count: 3, shuffle: false, repeatMode: 2, randomPick: det) == 1)
        #expect(QueueAdvance.nextIndex(current: 1, count: 3, shuffle: false, repeatMode: 2,
                                       manualSkip: true, randomPick: det) == 2)
        // repeat-one is checked BEFORE shuffle: an auto-advance repeats `current` even with
        // shuffle on (swapping those branches would silently randomize repeat-one).
        #expect(QueueAdvance.nextIndex(current: 1, count: 3, shuffle: true, repeatMode: 2, randomPick: det) == 1)
    }

    @Test("VM-QA-05: empty queue → nil (next and previous)")
    func emptyQueue() {
        #expect(QueueAdvance.nextIndex(current: 0, count: 0, shuffle: false, repeatMode: 1, randomPick: det) == nil)
        #expect(QueueAdvance.previousIndex(current: 0, count: 0, shuffle: false, repeatMode: 1, randomPick: det) == nil)
    }

    @Test("VM-QA-06: previous steps back; first-track no-repeat → nil; repeat-all wraps to last")
    func previousBehaviour() {
        #expect(QueueAdvance.previousIndex(current: 2, count: 3, shuffle: false, repeatMode: 0, randomPick: det) == 1)
        #expect(QueueAdvance.previousIndex(current: 0, count: 3, shuffle: false, repeatMode: 0, randomPick: det) == nil)
        #expect(QueueAdvance.previousIndex(current: 0, count: 3, shuffle: false, repeatMode: 1, randomPick: det) == 2)
    }

    @Test("VM-QA-07: shuffle calls the injected picker; single-track shuffle takes the linear branch")
    func shuffleUsesInjectedPicker() {
        #expect(QueueAdvance.nextIndex(current: 2, count: 5, shuffle: true, repeatMode: 0, randomPick: det) == 3)
        #expect(QueueAdvance.previousIndex(current: 2, count: 5, shuffle: true, repeatMode: 0, randomPick: det) == 3)
        // count == 1 → the `shuffle && count > 1` guard is false, so no picker call.
        #expect(QueueAdvance.nextIndex(current: 0, count: 1, shuffle: true, repeatMode: 1, randomPick: det) == 0)
    }

    @Test("VM-QA-08: uniformRandomExcluding stays in range and never returns current")
    func productionPickerProperty() {
        for current in 0 ..< 6 {
            for _ in 0 ..< 200 {
                let pick = QueueAdvance.uniformRandomExcluding(current, 6)
                #expect(pick >= 0 && pick < 6 && pick != current)
            }
        }
    }

    @Test("VM-QA-09: appendArmIndex arms only the linear end-of-queue case")
    func appendArmIndexDecision() {
        // Linear end-of-queue, repeat-off, nothing on-deck → arm the first appended (oldCount).
        #expect(QueueAdvance.appendArmIndex(current: 2, oldCount: 3, hasPending: false,
                                            shuffle: false, repeatMode: 0) == 3)
        // Mid-list → leave.
        #expect(QueueAdvance.appendArmIndex(current: 0, oldCount: 3, hasPending: false,
                                            shuffle: false, repeatMode: 0) == nil)
        // Already on-deck → leave.
        #expect(QueueAdvance.appendArmIndex(current: 2, oldCount: 3, hasPending: true,
                                            shuffle: false, repeatMode: 0) == nil)
        // Shuffle → leave (never re-roll).
        #expect(QueueAdvance.appendArmIndex(current: 2, oldCount: 3, hasPending: false,
                                            shuffle: true, repeatMode: 0) == nil)
        // Repeat-all → leave (it already wraps to 0).
        #expect(QueueAdvance.appendArmIndex(current: 2, oldCount: 3, hasPending: false,
                                            shuffle: false, repeatMode: 1) == nil)
        // Repeat-one → leave (auto-advance repeats current, never reaches the appended track).
        #expect(QueueAdvance.appendArmIndex(current: 2, oldCount: 3, hasPending: false,
                                            shuffle: false, repeatMode: 2) == nil)
    }
}
