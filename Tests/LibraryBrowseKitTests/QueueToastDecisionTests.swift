import LibraryBrowseKit
import Testing

// MARK: - QueueToastDecision (S9.5 §10.4 — copy, silence, visibility)

@Suite("QueueToastDecision — copy / silence / visibility")
struct QueueToastDecisionTests {
    private func msg(_ verb: QueueVerb, _ count: Int, nowPlaying: Bool = false) -> String? {
        QueueToastDecision.message(verb: verb, addedCount: count, isNowPlayingTab: nowPlaying)
    }

    /// TOAST-1 — Play Now is always silent (immediate playback, not a queue add).
    @Test("Play Now → silent for any count")
    func playNowSilent() {
        #expect(msg(.playNow, 3) == nil)
        #expect(msg(.playNow, 0) == nil)
    }

    /// TOAST-2 — silent on the Now Playing tab for every verb (its panel already IS the queue).
    @Test("Now Playing tab → silent for every verb")
    func silentOnNowPlaying() {
        #expect(msg(.addToQueue, 2, nowPlaying: true) == nil)
        #expect(msg(.playNext, 1, nowPlaying: true) == nil)
        #expect(msg(.playNow, 2, nowPlaying: true) == nil)
    }

    @Test("Add to Queue → count buckets 0/1/N")
    func addToQueueBuckets() {
        #expect(msg(.addToQueue, 0) == "Already in Queue")
        #expect(msg(.addToQueue, 1) == "Added to Queue")
        #expect(msg(.addToQueue, 3) == "Added 3 to Queue")
    }

    @Test("Play Next → count buckets 0/1/N")
    func playNextBuckets() {
        #expect(msg(.playNext, 0) == "Already in Queue")
        #expect(msg(.playNext, 1) == "Playing Next")
        #expect(msg(.playNext, 5) == "Added 5 to Play Next")
    }
}
