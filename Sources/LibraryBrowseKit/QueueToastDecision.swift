// MARK: - QueueToastDecision (S9.5 §10.4 — pure queue-toast copy decision)

/// The queue-add verb a toast can confirm.
public enum QueueVerb: Sendable {
    case playNow // immediate playback — always silent
    case playNext
    case addToQueue
}

/// Pure decision for the queue-add confirmation toast: given the verb, the actually-added count
/// (post-dedup, OD-2), and whether the Now Playing tab is showing (whose panel already *is* the
/// queue), returns the toast message — or `nil` to stay silent. Extracted so the copy + the
/// silence/visibility rules are unit-tested directly (the app model that drives the timer/coalescing
/// lives in the non-`@testable` executable). Copy per design §10.4.
public enum QueueToastDecision {
    public static func message(verb: QueueVerb, addedCount: Int, isNowPlayingTab: Bool) -> String? {
        // Silent on the Now Playing tab (its right panel is the queue) and for Play Now (immediate).
        guard !isNowPlayingTab, verb != .playNow else { return nil }
        switch addedCount {
        case 0: return "Already in Queue" // every input was already queued
        case 1: return verb == .playNext ? "Playing Next" : "Added to Queue"
        default: return "Added \(addedCount) to \(verb == .playNext ? "Play Next" : "Queue")"
        }
    }
}
