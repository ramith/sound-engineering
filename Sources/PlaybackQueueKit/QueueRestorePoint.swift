// PlaybackQueueKit — the one-level "Restore previous queue" point (S10.3 D-play; S10.8 E fix round).
//
// Pure and generic over the queue's slot, so the rule for which queue an undoable replace remembers
// is unit-tested without the engine or the view model (`QueueRestorePointTests`).

/// What "Restore previous queue" brings back after an undoable replace ("Play" on a page): the queue
/// the replace took away — its slots, the selected index and whether shuffle was on — and the slots the
/// replace INSTALLED, which is how the next replace tells the user's own queue from one a replace put
/// there.
public struct QueueRestorePoint<Slot: Identifiable> {
    /// The queue to bring back, and the slot that was selected in it.
    public let slots: [Slot]
    public let index: Int?
    /// Whether shuffle was on before the replace (a Shuffle replace turns it on).
    public let shuffle: Bool
    /// The slots the replace installed, in order.
    public let installed: [Slot.ID]

    public init(slots: [Slot], index: Int?, shuffle: Bool, installed: [Slot.ID]) {
        self.slots = slots
        self.index = index
        self.shuffle = shuffle
        self.installed = installed
    }

    /// The point to hold once an undoable replace has installed `installed` over the queue `replaced`
    /// (selected at `index`, with shuffle `shuffle`).
    ///
    /// While the queue being replaced is still the one the `held` point's replace installed — the same
    /// slots in the same order, so nothing was added, removed or moved since — the replace only
    /// replaced a replace: a double-click, a held Return, Play then Shuffle. `held` keeps what it
    /// restores, so the undo still brings back the user's own queue rather than the first replace's.
    /// Any other queue is the user's, and is what the new point restores.
    public static func afterReplace(held: QueueRestorePoint?, replaced: [Slot], index: Int?, shuffle: Bool,
                                    installed: [Slot.ID]) -> QueueRestorePoint {
        if let held, held.installed == replaced.map(\.id) {
            return QueueRestorePoint(slots: held.slots, index: held.index, shuffle: held.shuffle, installed: installed)
        }
        return QueueRestorePoint(slots: replaced, index: index, shuffle: shuffle, installed: installed)
    }
}

extension QueueRestorePoint: Sendable where Slot: Sendable, Slot.ID: Sendable {}
