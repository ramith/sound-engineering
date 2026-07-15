import PlaybackQueueKit
import Testing

// MARK: - NowPlayingSnapshot — the pure Now-Playing display decisions (S10.4)

@Suite("PlaybackQueueKit — NowPlayingSnapshot")
struct NowPlayingSnapshotTests {
    private func make(
        artist: String = "Miles Davis", album: String? = "Kind of Blue", state: NowPlayingState = .playing
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: "So What", artistName: artist, albumName: album,
            durationSeconds: 545, elapsedSeconds: 120, state: state,
            artworkKey: "abc", trackToken: "t1"
        )
    }

    @Test("NP-01: empty artist is omitted (nil), non-empty is kept")
    func emptyArtistOmitted() {
        #expect(make(artist: "").artist == nil)
        #expect(make(artist: "Miles Davis").artist == "Miles Davis")
    }

    @Test("NP-02: nil or empty album is omitted (nil)")
    func emptyAlbumOmitted() {
        #expect(make(album: nil).album == nil)
        #expect(make(album: "").album == nil)
        #expect(make(album: "Kind of Blue").album == "Kind of Blue")
    }

    @Test("NP-03: rate is 1.0 playing, 0.0 paused/stopped")
    func rateFromState() {
        #expect(make(state: .playing).rate == 1.0)
        #expect(make(state: .paused).rate == 0.0)
        #expect(make(state: .stopped).rate == 0.0)
    }

    @Test("NP-04: title / duration / elapsed / artworkKey / token pass through unchanged")
    func passthrough() {
        let snapshot = make()
        #expect(snapshot.title == "So What")
        #expect(snapshot.durationSeconds == 545)
        #expect(snapshot.elapsedSeconds == 120)
        #expect(snapshot.artworkKey == "abc")
        #expect(snapshot.trackToken == "t1")
    }

    // MARK: isStopped — the "clear Now Playing" decision (S10.4 FN-1)

    @Test("NP-05: stopped = not playing, at 0, no resume point (Stop / end-of-queue / fresh restore)")
    func stoppedState() {
        #expect(NowPlayingSnapshot.isStopped(isPlaying: false, elapsedSeconds: 0, hasResumePoint: false))
    }

    @Test("NP-06: playing is never stopped, even at position 0")
    func playingNotStopped() {
        #expect(!NowPlayingSnapshot.isStopped(isPlaying: true, elapsedSeconds: 0, hasResumePoint: false))
        #expect(!NowPlayingSnapshot.isStopped(isPlaying: true, elapsedSeconds: 42, hasResumePoint: false))
    }

    @Test("NP-07: paused-mid-track is not stopped — a resume point OR a non-zero position keeps it shown")
    func pausedNotStopped() {
        // Pause records a resume point (even a resume point of 0 → paused at the very start).
        #expect(!NowPlayingSnapshot.isStopped(isPlaying: false, elapsedSeconds: 0, hasResumePoint: true))
        // Or a non-zero elapsed (paused mid-track).
        #expect(!NowPlayingSnapshot.isStopped(isPlaying: false, elapsedSeconds: 90, hasResumePoint: false))
    }
}
