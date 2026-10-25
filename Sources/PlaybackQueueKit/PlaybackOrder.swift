// PlaybackQueueKit — the play order (shuffle + repeat): what plays after the song playing, what Previous
// plays, and what is armed next when the order changes mid-song (S10.8 G) or the queue is edited mid-song
// (council C-17).
//
// Pure + `Sendable`, so the rule is unit-tested without the engine or the view model
// (`PlaybackOrderTests`). Shuffle is the `ShufflePass` the view model keeps (R1.1-B, council C-16); the
// queue's own order is `QueueAdvance`. Rows are the queue's indices; `row` finds a pass's slot in it.

/// Shuffle and repeat together: the rule the view model's next, previous and on-deck picks follow.
public struct PlaybackOrder: Sendable {
    let shuffle: Bool
    /// 0 = off, 1 = all, 2 = one (matching `AudioViewModel.repeatMode`).
    let repeatMode: Int

    public init(shuffle: Bool, repeatMode: Int) {
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }

    /// The row that plays after `current` in a queue of `count` rows. An automatic advance under Repeat One
    /// plays the song again; a manual Next (`manualSkip`) steps on. Under shuffle, the pass's next song:
    /// at the end of the pass, its next pass with Repeat All, nothing with Repeat off — a manual Next under
    /// Repeat One steps as under Repeat off. In order, the next row, Repeat All wrapping after the last.
    ///
    /// Also what to arm once the order changed mid-song (S10.8 G), so the change applies to the end of THIS
    /// song: Repeat One arms the song itself, leaving it arms the next song, shuffle turned on arms the new
    /// pass's next, turned off the next row; a repeat change under shuffle keeps the pass's pick, except at
    /// the pass's end, where Repeat off now ends the queue. Returns nil when nothing should play.
    public func next<Slot>(after current: Int, count: Int, manualSkip: Bool = false, pass: ShufflePass<Slot>?,
                           row: (Slot) -> Int?) -> Int? {
        guard count > 0 else { return nil }
        if repeatMode == 2, !manualSkip {
            return current
        }
        if shuffle, let pass {
            return pass.peekNext(repeatMode: repeatMode == 1 ? 1 : 0).flatMap(row)
        }
        return QueueAdvance.nextIndex(current: current, count: count, repeatMode: repeatMode, manualSkip: manualSkip)
    }

    /// The row Previous plays from `current`. Under shuffle, the song that played before it in the pass —
    /// at the pass's first song, the last pass's last song with Repeat All, else the song itself again (a
    /// restart; founder, 2026-10-25). In order, the row before, Repeat All wrapping to the last; nil at the
    /// first row otherwise.
    public func previous<Slot>(before current: Int, count: Int, pass: ShufflePass<Slot>?,
                               row: (Slot) -> Int?) -> Int? {
        guard count > 0 else { return nil }
        if shuffle, let pass {
            return pass.previous(repeatMode: repeatMode).flatMap(row)
        }
        return QueueAdvance.previousIndex(current: current, count: count, repeatMode: repeatMode)
    }

    /// The row to arm after the queue was edited while `current` plays — an append, a move, a removal — so
    /// the edit applies to the end of THIS song (council C-17). `current` and `armed` are rows in the
    /// edited queue: the armed pick found again by its slot (`nil`: nothing was armed, or the edit removed
    /// it).
    ///
    /// - Under Repeat One the armed pick stands: this song, or a Play Next armed over it.
    /// - Under shuffle, the pass's next: the pass placed an added song after the one armed, so the armed
    ///   pick stands — never re-rolled — and a removed one gives way to the song after it in the pass.
    /// - In order, the row after the playing one as the queue now reads (VLC and foobar2000 compute it at
    ///   the track's end): a song dragged in under the playing one plays next, the next song dragged away
    ///   doesn't, an append to the last song plays next — Repeat All wraps only after it.
    ///
    /// Returns `nil` when nothing should play after `current`.
    public func onDeck<Slot>(afterEditing current: Int, count: Int, armed: Int?, pass: ShufflePass<Slot>?,
                             row: (Slot) -> Int?) -> Int? {
        if repeatMode == 2, let armed {
            return armed
        }
        return next(after: current, count: count, pass: pass, row: row)
    }
}
