import Foundation

// MARK: - AudioViewModel transport (track selection / skip / press-play)

@MainActor
extension AudioViewModel {
    /// Play the track at the given playlist index.
    func playTrack(at index: Int) {
        guard index < playlist.count else { return }
        selectedTrackIndex = index
        startPlayback()
    }

    /// Press-Play entry point. When nothing is selected yet (e.g. right after loading a folder),
    /// pick the starting track — the first track, or a random one when shuffle is on — then play.
    /// If a track is already selected, (re)starts it. (Previously Play did nothing with no
    /// selection, so a freshly-loaded folder wouldn't start on the first Play press.)
    func play() {
        if selectedTrackIndex == nil {
            guard !playlist.isEmpty else { return }
            selectedTrackIndex = shuffleEnabled ? Int.random(in: 0 ..< playlist.count) : 0
        }
        startPlayback()
    }

    /// Skip to the next track (linear). If currently playing, switches the ENGINE to the new
    /// track (calls startPlayback, which also re-arms the gapless on-deck); if paused, just
    /// re-selects. (Previously the transport buttons only moved `selectedTrackIndex`, so the
    /// GUI advanced but the audio kept playing the old track.)
    func nextTrack() {
        guard let current = selectedTrackIndex else { return }
        let next = current + 1
        guard next < playlist.count else { return }
        selectedTrackIndex = next
        if isPlaying { startPlayback() }
    }

    /// Skip to the previous track (linear). Same play-if-playing semantics as `nextTrack()`.
    func previousTrack() {
        guard let current = selectedTrackIndex, current > 0 else { return }
        selectedTrackIndex = current - 1
        if isPlaying { startPlayback() }
    }
}
