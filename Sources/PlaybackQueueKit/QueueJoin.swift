// PlaybackQueueKit — the launch's join: what the listener queued before the stored queue came back (R1.1-B;
// review M2, break-it BI-P03).
//
// A file opened at launch (Open With, a drop on the Dock icon, Open…) can reach the queue before the store is
// ready and the stored queue is restored. Neither is thrown away: the restored queue is put in place, and what
// came before joins it where doing the same AFTER the restore would have put it — so the two orders end in the
// same queue, the same song playing, the same song next and the same record.
//
// An open plays its first file now and queues the rest after it (`playTrackNextNow`, then Play Next). So the
// song the listener started joins by `QueueInsert.playNextNow`: right after the restored song — first when none
// is selected — with the restored queue's first slot of the same file moved there, or, when that slot is the
// restored song itself, in its place; what was queued before travels with it, in its own order. Under shuffle
// the restored pass goes on: what joins plays next, in order, counted as played (Play Next's rule), the song
// started being the pass's song. With nothing started (an Add to Queue) it all goes at the end, and under
// shuffle each song to a random place after the song armed next, as an append does — the same draws.
//
// Exact for one open, or several, before the restore. Not for one rarer order: two opens before it, the first
// of a file the restored queue holds — only the song started last finds its restored slot.

/// The queue the launch's restore puts in place: the restored queue joined by what came before it.
public struct QueueJoined<Item: Identifiable> where Item.ID: Sendable {
    /// The queue, in order.
    public let items: [Item]
    /// The row to select: the song started before the restore's, else the restored song's; nil when neither.
    public let selected: Int?
    /// The shuffle pass, on the selected song; nil with shuffle off, or nothing selected.
    public let pass: ShufflePass<Item.ID>?
}

public extension QueueResumeRecord.Resolved where Item: Identifiable, Item.ID: Sendable {
    /// This restored queue joined by `before` — the queue before the restore, its row `started` the song the
    /// listener started there (nil: none) — as doing the same after the restore would leave it (see the file's
    /// header). `shuffled`: shuffle is on, and the restored pass goes on. `isSameSong`: two items play the
    /// same file.
    func joined(by before: [Item], started: Int?, shuffled: Bool,
                isSameSong: (Item, Item) -> Bool) -> QueueJoined<Item> {
        let restoredPass = shuffled ? shuffle : nil
        guard let started else {
            let joined = items + before
            var pass = restoredPass?.relabeled { items[$0].id }
            pass?.follow(joined.map(\.id))
            return QueueJoined(items: joined, selected: cursor, pass: pass)
        }
        let place = placeOfStarted(before[started], isSameSong)
        var kept = items
        if let moved = place.moving {
            kept.remove(at: moved)
        }
        let joined = Array(kept[..<place.at]) + before + Array(kept[place.at...])
        var pass = restoredPass?.relabeled { $0 == place.moving ? nil : items[$0].id }
        pass?.insertNext(before.map(\.id))
        for item in before[...started] { // a step at a time onto the song started: it plays now
            pass?.arrive(at: item.id)
        }
        return QueueJoined(items: joined, selected: place.at + started, pass: pass)
    }

    /// Where the song started goes: the row `at` in the restored queue without the row `moving` — its slot of
    /// the same file that the song started takes over, if any.
    private func placeOfStarted(_ song: Item, _ isSameSong: (Item, Item) -> Bool) -> (moving: Int?, at: Int) {
        let move = QueueInsert.playNextNow(current: cursor, count: items.count) { isSameSong(items[$0], song) }
        switch move {
        case let .restartCurrent(index):
            return (index, index)
        case let .insertAndPlay(removeAt, insertAt):
            return (removeAt, insertAt)
        }
    }
}
