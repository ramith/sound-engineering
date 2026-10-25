// PlaybackQueueKit — the random numbers a shuffle pass draws (R1.1-B).
//
// A pass keeps its randomness as one number (`ShufflePass.seed`), so the pass — and every pass after
// it — reproduces from the stored value after a crash, and a test seeds it. SplitMix64 (Steele, Lea &
// Flood 2014) has exactly that: a 64-bit state, every output from one add and a fixed mix.

/// SplitMix64, with the two draws a shuffle pass makes: a bounded number, and a Fisher–Yates shuffle.
///
/// The bounded draw is fixed here (Lemire's multiply-high, no rejection) rather than the standard
/// library's `random(in:using:)`, whose method may change between Swift releases: a kept seed must draw
/// the same pass after an app update. Its bias is at most `bound / 2⁶⁴` — below 10⁻¹⁴ for any queue.
struct ShuffleGenerator {
    /// The whole state: what the pass stores as its `seed`.
    var state: UInt64

    /// The next 64 random bits.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A number in `0 ..< bound`; `bound` must be positive.
    mutating func below(_ bound: Int) -> Int {
        precondition(bound > 0, "a bounded draw needs a positive bound")
        return Int(next().multipliedFullWidth(by: UInt64(bound)).high)
    }

    /// Fisher–Yates (Durstenfeld): every order of `elements` equally likely.
    mutating func shuffle<Element>(_ elements: inout [Element]) {
        guard elements.count > 1 else { return }
        for last in stride(from: elements.count - 1, to: 0, by: -1) {
            elements.swapAt(last, below(last + 1))
        }
    }
}
