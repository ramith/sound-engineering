// PlaybackQueueKit — many songs into a shuffle pass at once (R1.1-B, review S3).
//
// `ShufflePass.follow` puts each song added to the queue at a random place after the song armed next, as if
// the songs came one at a time — each into the pass as the one before it left it. Done literally that is an
// array insert per song: a 20,000-song Add to Queue shifted the pass's line about 10⁸ slots, on the main
// actor, inside the queue's didSet. The places are drawn the same way, so a kept seed still draws the same
// pass; only the building changes — once, here.

/// Building a line with many slots put into it, as one-at-a-time inserts would put them.
enum LineInterleave {
    /// `line` with each of `added` put in it: `added[k]` at `offsets[k]` — its place in the line as the slots
    /// before it in `added` left it, `0 ... line.count + k`. The same line inserting them one at a time, in
    /// order, makes; built in one pass.
    ///
    /// Backwards: the last slot inserted is where it was put, as nothing came after it; each slot before it is
    /// at its offset among the places the later ones did not take. `FreePlaces` finds that place in log time,
    /// so the whole costs the line's length plus m log of it, for m slots added.
    static func interleaved<Slot>(_ line: ArraySlice<Slot>, inserting added: [Slot], at offsets: [Int]) -> [Slot] {
        let length = line.count + added.count
        var free = FreePlaces(count: length)
        var addedAt = [Int](repeating: -1, count: length) // per place: the index in `added` that goes there
        for order in added.indices.reversed() {
            addedAt[free.take(offsets[order])] = order
        }
        var built: [Slot] = []
        built.reserveCapacity(length)
        var kept = line.startIndex
        for order in addedAt {
            if order >= 0 {
                built.append(added[order])
            } else {
                built.append(line[kept])
                kept += 1
            }
        }
        return built
    }
}

/// The places `0 ..< count` of a line, each free until taken: the `rank`-th free one is found, and taken, in
/// log time. A Fenwick tree (Fenwick 1994) over the places' "free" flags.
struct FreePlaces {
    /// 1-based: `tree[i]` counts the free places in `(i - lowbit(i)) ..< i`, numbered from 0.
    private var tree: [Int]
    /// The highest power of two not above the count: where the descent for a rank starts.
    private let top: Int

    init(count: Int) {
        // Every place free: each node counts exactly the places it covers, its low bit.
        tree = [0] + (0 ..< count).map { ($0 + 1) & -($0 + 1) }
        top = count > 0 ? 1 << (Int.bitWidth - 1 - count.leadingZeroBitCount) : 0
    }

    /// Take the free place of `rank` (0: the first free one) and return it. `rank` must name a free place.
    mutating func take(_ rank: Int) -> Int {
        // Descend to the last node whose prefix holds no more than `rank` free places: the next is the place.
        var node = 0
        var remaining = rank
        var step = top
        while step > 0 {
            let next = node + step
            if next < tree.count, tree[next] <= remaining {
                node = next
                remaining -= tree[next]
            }
            step >>= 1
        }
        var covering = node + 1
        while covering < tree.count {
            tree[covering] -= 1
            covering += covering & -covering
        }
        return node
    }
}
