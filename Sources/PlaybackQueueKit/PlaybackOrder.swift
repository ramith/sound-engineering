// PlaybackQueueKit — the play order (shuffle + repeat), and what it arms next when it changes mid-song
// (S10.8 G) or the queue is edited mid-song (council C-17).
//
// Pure + `Sendable`, so the rule is unit-tested without the engine or the view model
// (`PlaybackOrderTests`). The shuffle choice is the INJECTED picker `QueueAdvance` takes.

/// Shuffle and repeat together: the rule `QueueAdvance.nextIndex` picks the next song by.
public struct PlaybackOrder: Sendable {
    let shuffle: Bool
    /// 0 = off, 1 = all, 2 = one (matching `AudioViewModel.repeatMode`).
    let repeatMode: Int

    public init(shuffle: Bool, repeatMode: Int) {
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }

    /// The song to arm next when the user switches to this order from `old` while `current` plays,
    /// so the switch applies to the end of THIS song (the armed pick was made under `old`).
    ///
    /// - Repeat One arms this song again; leaving Repeat One arms the next song.
    /// - A shuffle pick (`armed`) stands while shuffle stays on and Repeat One is in neither order:
    ///   repeat all / off never change a shuffle pick, and re-rolling would throw it away — with a
    ///   Play Next pick armed over it (a primed pick is never re-rolled, design §6).
    /// - Otherwise the next song under this order: Repeat All on the last song wraps to the first,
    ///   Repeat off ends after it, shuffle on picks at random, shuffle off goes on in order.
    ///
    /// Returns `nil` when nothing should play after `current`.
    public func onDeck(switchingFrom old: PlaybackOrder, current: Int, count: Int, armed: Int?,
                       randomPick: (Int, Int) -> Int) -> Int? {
        let shufflePickStands = old.shuffle && shuffle && old.repeatMode != 2 && repeatMode != 2
        if shufflePickStands, let armed {
            return armed
        }
        return QueueAdvance.nextIndex(current: current, count: count, shuffle: shuffle, repeatMode: repeatMode,
                                      randomPick: randomPick)
    }

    /// The song to arm next after the queue was edited while `current` plays — an append, a move, a
    /// removal — so the edit applies to the end of THIS song (council C-17). `current` and `armed` are
    /// rows in the edited queue: the armed pick found again by its slot (`nil`: nothing was armed, or the
    /// edit removed it).
    ///
    /// - In order, next is the row after the current one, as the queue now reads (VLC and foobar2000
    ///   compute it at the track's end): a song dragged in under the playing one plays next, the next
    ///   song dragged away doesn't, an append to the last song plays next — Repeat All wraps only after it.
    /// - A pick the order did not take by position stands: a shuffle pick (an edit never re-rolls it),
    ///   and under Repeat One this song, or a Play Next armed over it.
    /// - With nothing armed, the next song under this order: a one-song shuffle that grew plays the new
    ///   song.
    ///
    /// Returns `nil` when nothing should play after `current`.
    public func onDeck(afterEditing current: Int, count: Int, armed: Int?,
                       randomPick: (Int, Int) -> Int) -> Int? {
        if let armed, shuffle || repeatMode == 2 {
            return armed
        }
        return QueueAdvance.nextIndex(current: current, count: count, shuffle: shuffle, repeatMode: repeatMode,
                                      randomPick: randomPick)
    }
}
