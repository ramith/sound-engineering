// PlaybackQueueKit — the play order (shuffle + repeat), and what changing it mid-song arms next
// (S10.8 G).
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
}
