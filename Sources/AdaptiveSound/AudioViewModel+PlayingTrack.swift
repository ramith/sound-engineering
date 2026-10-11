import Foundation

// MARK: - AudioViewModel + the playing library song (S10.8 E2)

extension AudioViewModel {
    /// The library id of the song playing now — the row the Library lists draw as playing (Songs,
    /// the album, artist and genre pages). Nil while paused or stopped, and for a file opened from
    /// outside the library.
    var playingTrackID: Int64? {
        guard isPlaying, let index = selectedTrackIndex, index < queue.count else { return nil }
        return queue[index].file.trackID
    }
}
