// PlaybackQueueKit — shuffle as a permutation with history (R1.1-B; council C-16, KI-PB-03).
//
// Shuffle used to pick a random other song at every end (`QueueAdvance`'s injected picker): songs came
// round again before others had played, nothing remembered what played, Previous was one more random
// song, and with Repeat off the queue never ended (KI-PB-03). A pass is the rule instead: every song of
// the queue once, in an order drawn up front (Fisher–Yates), so Previous walks back through what played
// and Next after Previous goes on in the same order — it never re-rolls. Repeat off ends the queue after
// the pass; Repeat All starts a new pass that never begins with the song that just ended. At a pass's
// first song, Previous goes back into the last pass with Repeat All and restarts the song with Repeat off
// (founder, 2026-10-25). The pass is not shown: Up Next keeps the queue's own order (founder, 2026-10-25).
//
// Pure and `Sendable`, generic over the slot's identity — the app's `QueueItem.id`; the stored record's
// row index (`QueueResumeRecord`) — and every random choice is drawn from its own generator, whose whole
// state it keeps (`seed`). So a pass, and the passes after it, reproduce from the value alone: a test
// seeds it, and a crash restore brings back the same order, place and history.

/// One shuffled pass through the queue: every song once, in a random order; the pass before it, as it
/// played; and where the listener is.
///
/// Think of the two orders as one line — the last pass (`history`), then this one (`permutation`) — with
/// the song playing at `position` on it. Moving on is a step to the right, Previous a step to the left;
/// the edits keep both orders whole: a slot is held at most once by each, and every slot of the queue by
/// one of them.
public struct ShufflePass<Slot: Hashable & Sendable>: Sendable, Equatable {
    /// This pass's order: each slot of the queue once. (A slot added while the listener was back in the
    /// last pass plays there, and is held by `history` only: it counts as played in this pass.)
    public private(set) var permutation: [Slot]
    /// The last pass, in the order it played: what Previous walks back into from this pass's first song
    /// under Repeat All. Empty in the first pass.
    public private(set) var history: [Slot]
    /// The song playing: its index in `permutation`. Negative counts back into `history` (−1 is the last
    /// pass's last song); `-history.count - 1` stands before every song (the song playing at the very
    /// start was removed).
    public private(set) var position: Int
    /// The state of the generator every random choice of the pass is drawn from: the order of the next
    /// pass, where an added song goes. The whole of its randomness, kept.
    public private(set) var seed: UInt64

    // MARK: - Making a pass

    /// A pass that begins at `first` — playing now — with the rest of `slots` after it in random order,
    /// drawn from `seed`. Shuffle turned on mid-song, or a song started with shuffle on.
    public init(beginningAt first: Slot, among slots: [Slot], seed: UInt64) {
        var generator = ShuffleGenerator(state: seed)
        var rest = slots.filter { $0 != first }
        generator.shuffle(&rest)
        permutation = [first] + rest
        history = []
        position = 0
        self.seed = generator.state
    }

    /// A kept pass, if it holds together: neither order holds a slot twice, and `position` is on the line.
    public init?(permutation: [Slot], history: [Slot], position: Int, seed: UInt64) {
        guard Set(permutation).count == permutation.count, Set(history).count == history.count,
              position >= -history.count - 1, position < permutation.count else { return nil }
        self.permutation = permutation
        self.history = history
        self.position = position
        self.seed = seed
    }

    // MARK: - Where the listener is

    /// The song playing; nil when the song playing at the very start was removed.
    public var current: Slot? {
        cursor >= 0 ? slot(at: cursor) : nil
    }

    /// What plays after the song playing when it ends, under `repeatMode` (0 off, 1 all, 2 one): Repeat One
    /// the song itself; else the pass's next song; at the end of the pass, the next pass's first song with
    /// Repeat All — drawn from `seed`, the same draw `arrive(at:)` makes when the pass gets there — and nil
    /// with Repeat off: the queue ends.
    ///
    /// The song after THAT one (Auto leveling's neighbour): `arrive(at:)` on a copy, then this.
    public func peekNext(repeatMode: Int) -> Slot? {
        if repeatMode == 2, let current {
            return current
        }
        if cursor + 1 < count {
            return slot(at: cursor + 1)
        }
        return repeatMode == 1 ? nextPass().order.first : nil
    }

    /// What Previous plays, under `repeatMode`: the song that played before this one — at this pass's first
    /// song, the last pass's last song with Repeat All — else the song itself again (a restart). Nil when no
    /// song is playing.
    public func previous(repeatMode: Int) -> Slot? {
        guard let current else { return nil }
        return stepsBack(repeatMode: repeatMode) ? slot(at: cursor - 1) : current
    }

    // MARK: - Moving

    /// Previous: one step back (`previous(repeatMode:)`); a restart leaves the pass as it is.
    public mutating func stepBack(repeatMode: Int) {
        if current != nil, stepsBack(repeatMode: repeatMode) {
            position -= 1
        }
    }

    /// The song playing is now `slot`. Its pass's next song (a seam, or Next) is a step on; the song itself
    /// (Repeat One, a restart) changes nothing. At the end of the pass the next pass begins: with the song
    /// `peekNext` named (Repeat All), or with the song the listener chose and the rest in a fresh order.
    /// Any other song is the listener's choice: it plays now and counts as played — it moves to just after
    /// the song that was playing, so the rest of the pass keeps its order.
    public mutating func arrive(at slot: Slot) {
        if cursor + 1 < count, self.slot(at: cursor + 1) == slot {
            position += 1
            return
        }
        guard current != slot else { return }
        guard cursor + 1 < count else {
            beginNextPass(with: slot)
            return
        }
        remove { $0 == slot }
        insert([slot], at: cursor + 1)
        position += 1
    }

    // MARK: - Edits

    /// Play Next: `slots` play right after the song playing, in order, and count as played in this pass
    /// (R1.1-B §6 shuffle 6). A slot the pass already holds moves there. One splice, however many (review S3).
    public mutating func insertNext(_ slots: [Slot]) {
        let moving = Set(slots)
        remove { moving.contains($0) }
        insert(slots, at: cursor + 1)
    }

    /// The queue now holds `slots`. A slot it no longer holds leaves both orders (Previous skips it). A slot
    /// the pass doesn't hold yet goes to a random place in this pass after the song armed next — so it plays
    /// once in this pass, and the armed pick stands (council C-17). Played next only when nothing is left
    /// after the song playing.
    ///
    /// The added slots are placed as if they came one at a time, in `slots`' order, each into the pass as the
    /// one before it left it — every place drawn first, the same draws — and the line is then built once: a
    /// 20,000-song Add to Queue costs one pass over the queue, not a shift of it per song (review S3).
    public mutating func follow(_ slots: [Slot]) {
        let queued = Set(slots)
        remove { !queued.contains($0) }
        let held = Set(history).union(permutation)
        let added = slots.filter { !held.contains($0) }
        guard !added.isEmpty else { return }
        // Each place is an offset from `start`, where the first added slot may go; the songs at and before the
        // one armed next stay where they are (none moves: every place is after the song playing).
        let start = min(max(cursor + 2, history.count), count)
        var generator = ShuffleGenerator(state: seed)
        let offsets = added.indices.map { order in
            let length = count + order // the line as the slots added before this one left it
            let earliest = min(max(cursor + 2, history.count), length)
            return earliest - start + generator.below(length - earliest + 1)
        }
        seed = generator.state
        let tail = start - history.count
        let line = LineInterleave.interleaved(permutation[tail...], inserting: added, at: offsets)
        ShufflePassTally.current?.add(line.count)
        permutation.replaceSubrange(tail..., with: line)
    }

    /// The same pass over other identities — the stored record's row indices, the restored queue's slots. A
    /// slot `transform` names nothing for leaves the pass as a removal does. Nil if two slots come out as one.
    public func relabeled<Other: Hashable & Sendable>(_ transform: (Slot) -> Other?) -> ShufflePass<Other>? {
        var removedUpToCursor = 0
        func relabel(_ slots: [Slot], from start: Int) -> [Other] {
            slots.enumerated().compactMap { offset, slot in
                let other = transform(slot)
                if other == nil, start + offset <= cursor {
                    removedUpToCursor += 1
                }
                return other
            }
        }
        let history = relabel(history, from: 0)
        let permutation = relabel(permutation, from: self.history.count)
        return ShufflePass<Other>(permutation: permutation, history: history,
                                  position: cursor - removedUpToCursor - history.count, seed: seed)
    }

    // MARK: - The line: history, then this pass

    /// How many songs are on the line.
    private var count: Int {
        history.count + permutation.count
    }

    /// The song playing, as an index on the line (−1: before every song).
    private var cursor: Int {
        history.count + position
    }

    private func slot(at index: Int) -> Slot {
        index < history.count ? history[index] : permutation[index - history.count]
    }

    /// Whether Previous steps back rather than restarting: there is a song before this one, and this is not
    /// the pass's first song — or it is, under Repeat All.
    private func stepsBack(repeatMode: Int) -> Bool {
        cursor > 0 && (position != 0 || repeatMode == 1)
    }

    /// Put `slots` at `index` on the line, in order, in one splice: in the last pass when the index is inside
    /// it, else in this pass. The song playing stays the song playing.
    private mutating func insert(_ slots: [Slot], at index: Int) {
        let playing = cursor
        ShufflePassTally.current?.add(count - index + slots.count)
        if index < history.count {
            history.insert(contentsOf: slots, at: index)
        } else {
            permutation.insert(contentsOf: slots, at: index - history.count)
        }
        position = (index <= playing ? playing + slots.count : playing) - history.count
    }

    /// Take every slot `isGone` names off the line. The song playing stays the song playing; when it goes
    /// itself, the line stands just after the song before it, so the song that was next is still next. The
    /// line is rebuilt only when a slot goes.
    private mutating func remove(where isGone: (Slot) -> Bool) {
        guard history.contains(where: isGone) || permutation.contains(where: isGone) else { return }
        let playing = cursor
        ShufflePassTally.current?.add(count)
        var removedUpToCursor = 0
        func kept(_ slots: [Slot], from start: Int) -> [Slot] {
            var kept: [Slot] = []
            kept.reserveCapacity(slots.count)
            for (offset, slot) in slots.enumerated() {
                if !isGone(slot) {
                    kept.append(slot)
                } else if start + offset <= playing {
                    removedUpToCursor += 1
                }
            }
            return kept
        }
        let lastPassCount = history.count
        history = kept(history, from: 0)
        permutation = kept(permutation, from: lastPassCount)
        position = playing - removedUpToCursor - history.count
    }

    /// The pass after this one: every slot once — this pass's, and any played only in the last pass — in a
    /// fresh random order that does not begin with the song that just ended, unless it is the only one.
    private func nextPass() -> (order: [Slot], seed: UInt64) {
        var generator = ShuffleGenerator(state: seed)
        let inPass = Set(permutation)
        var order = permutation + history.filter { !inPass.contains($0) }
        generator.shuffle(&order)
        if order.count > 1, let ended = current, order[0] == ended {
            order.swapAt(0, 1 + generator.below(order.count - 1))
        }
        return (order, generator.state)
    }

    /// The pass ran out and `first` plays: the next pass begins. The draw `peekNext` named, when it begins
    /// with `first`; otherwise `first`, then the rest in a fresh order. This pass becomes the history.
    private mutating func beginNextPass(with first: Slot) {
        let drawn = nextPass()
        let next = drawn.order.first == first
            ? ShufflePass(permutation: drawn.order, history: [], position: 0, seed: drawn.seed)
            : ShufflePass(beginningAt: first, among: drawn.order, seed: drawn.seed)
        guard let next else { return }
        history = permutation
        permutation = next.permutation
        position = 0
        seed = next.seed
    }
}

// MARK: - The stored form

extension ShufflePass: Codable where Slot: Codable {
    /// The stored field names are part of the persisted queue state: never rename one.
    private enum CodingKeys: String, CodingKey {
        case permutation, history, position, seed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let pass = try ShufflePass(permutation: container.decode([Slot].self, forKey: .permutation),
                                         history: container.decode([Slot].self, forKey: .history),
                                         position: container.decode(Int.self, forKey: .position),
                                         seed: container.decode(UInt64.self, forKey: .seed)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "a shuffle pass that does not hold together"))
        }
        self = pass
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permutation, forKey: .permutation)
        try container.encode(history, forKey: .history)
        try container.encode(position, forKey: .position)
        try container.encode(seed, forKey: .seed)
    }
}
