// NowPlayingSnapshot — the pure, MediaPlayer-free model of what to show in Now Playing (S10.4).
//
// The `NowPlayingController` (app target) builds one of these from `AudioViewModel` state on each
// coalesced push, then maps it to the `MPNowPlayingInfoCenter` dict + `playbackState`. Keeping the
// display DECISIONS here (empty artist/album → omitted; rate derived from state) makes them
// unit-testable without touching the MediaPlayer C-API (which mutates global system state).

public enum NowPlayingState: Sendable, Equatable {
    case playing
    case paused
    case stopped
}

public struct NowPlayingSnapshot: Sendable, Equatable {
    public let title: String
    /// nil when the source artist is empty (omit the key rather than show a blank).
    public let artist: String?
    /// nil when the source album is nil/empty.
    public let album: String?
    public let durationSeconds: Double
    public let elapsedSeconds: Double
    /// 1.0 while playing, else 0.0 — the second half of the macOS Now-Playing rate/state pair.
    public let rate: Double
    public let state: NowPlayingState
    /// Artwork cache key for async resolution (nil = no artwork; loose files / no key).
    public let artworkKey: String?
    /// Stable identity of the track this snapshot describes — the async artwork load applies its
    /// result only if this still matches the current track (stale-guard).
    public let trackToken: String

    /// Build from raw VM state, applying the display decisions: an empty artist/album is omitted,
    /// and the playback rate is derived from the state (1 playing, 0 paused/stopped).
    public init(
        title: String,
        artistName: String,
        albumName: String?,
        durationSeconds: Double,
        elapsedSeconds: Double,
        state: NowPlayingState,
        artworkKey: String?,
        trackToken: String
    ) {
        self.title = title
        artist = artistName.isEmpty ? nil : artistName
        album = (albumName?.isEmpty ?? true) ? nil : albumName
        self.durationSeconds = durationSeconds
        self.elapsedSeconds = elapsedSeconds
        rate = state == .playing ? 1.0 : 0.0
        self.state = state
        self.artworkKey = artworkKey
        self.trackToken = trackToken
    }
}
