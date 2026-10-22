import PlaybackQueueKit
import Testing

// MARK: - QueueRestorePoint — which queue "Restore previous queue" brings back (VM-QR)

//
// Imports the shipped `PlaybackQueueKit` target, so the rule the view model's undoable replace runs
// (`AudioViewModel.playNowWithUndo` / `shufflePlay`) is the rule under test. A slot's id is fresh per
// replace in the app (a UUID); here each replace installs new Int ids.

@Suite("PlaybackQueueKit — QueueRestorePoint, the one-level queue undo (VM-QR)")
struct QueueRestorePointTests {
    private struct Slot: Identifiable, Equatable {
        let id: Int
    }

    private typealias Point = QueueRestorePoint<Slot>

    private static func slots(_ ids: Int...) -> [Slot] {
        ids.map(Slot.init)
    }

    /// The user's own queue, playing its second song with shuffle off.
    private static let own = slots(1, 2, 3)

    /// The point a first Play leaves: the user's queue, replaced by slots 10–12.
    private static func afterFirstPlay() -> Point {
        Point.afterReplace(held: nil, replaced: own, index: 1, shuffle: false, installed: [10, 11, 12])
    }

    @Test("VM-QR-01: the first replace remembers the queue it took away — slots, index and shuffle")
    func firstReplace() {
        let point = Self.afterFirstPlay()
        #expect(point.slots == Self.own)
        #expect(point.index == 1)
        #expect(point.shuffle == false)
        #expect(point.installed == [10, 11, 12])
    }

    @Test("VM-QR-02: a second replace of the untouched installed queue keeps the user's queue (a double-click)")
    func replaceOfAReplaceKeepsThePoint() {
        let first = Self.afterFirstPlay()
        // The second click replaces the queue the first installed; the song has moved on meanwhile.
        let second = Point.afterReplace(held: first, replaced: Self.slots(10, 11, 12), index: 2, shuffle: false,
                                        installed: [20, 21, 22])
        #expect(second.slots == Self.own)
        #expect(second.index == 1)
        #expect(second.installed == [20, 21, 22])
    }

    @Test("VM-QR-03: a held key — every replace in the run still restores the user's queue")
    func heldKey() {
        var point = Self.afterFirstPlay()
        var installed = [10, 11, 12]
        for round in 2 ... 30 {
            let next = [round * 10, round * 10 + 1, round * 10 + 2]
            point = Point.afterReplace(held: point, replaced: installed.map(Slot.init), index: 0, shuffle: false,
                                       installed: next)
            installed = next
        }
        #expect(point.slots == Self.own)
        #expect(point.index == 1)
        #expect(point.installed == installed)
    }

    @Test("VM-QR-04: Play then Shuffle restores the user's shuffle setting, not the one Shuffle turned on")
    func shuffleAfterPlayKeepsTheOriginalShuffle() {
        let first = Self.afterFirstPlay()
        // Shuffle replaces Play's queue; shuffle is still off as it is replaced.
        let shuffled = Point.afterReplace(held: first, replaced: Self.slots(10, 11, 12), index: 0, shuffle: false,
                                          installed: [20, 21, 22])
        // A second Shuffle replaces the first: shuffle is on by now, yet the point keeps "off".
        let again = Point.afterReplace(held: shuffled, replaced: Self.slots(20, 21, 22), index: 1, shuffle: true,
                                       installed: [30, 31, 32])
        #expect(again.slots == Self.own)
        #expect(again.shuffle == false)
    }

    @Test("VM-QR-05: a first replace made with shuffle on remembers it on")
    func remembersShuffleOn() {
        let point = Point.afterReplace(held: nil, replaced: Self.own, index: 0, shuffle: true, installed: [10])
        #expect(point.shuffle == true)
    }

    @Test("VM-QR-06: an installed queue the user changed is the user's — added to, removed from, or reordered")
    func changedQueueIsSnapshotted() {
        let first = Self.afterFirstPlay()
        for changed in [Self.slots(10, 11, 12, 99), Self.slots(10, 12), Self.slots(11, 10, 12)] {
            let point = Point.afterReplace(held: first, replaced: changed, index: 0, shuffle: true, installed: [20])
            #expect(point.slots == changed)
            #expect(point.index == 0)
            #expect(point.shuffle == true)
        }
    }

    @Test("VM-QR-07: a queue some other play put there is the user's — the same songs in new slots, or none")
    func foreignQueueIsSnapshotted() {
        let first = Self.afterFirstPlay()
        // An album played since (not undoable): new slots, even if they hold the same songs.
        let album = Self.slots(40, 41, 42)
        let afterAlbum = Point.afterReplace(held: first, replaced: album, index: 2, shuffle: false, installed: [50])
        #expect(afterAlbum.slots == album)
        // The queue was cleared: an empty queue is what the new point restores.
        let cleared = Point.afterReplace(held: first, replaced: [], index: nil, shuffle: false, installed: [50])
        #expect(cleared.slots.isEmpty)
        #expect(cleared.index == nil)
    }
}
