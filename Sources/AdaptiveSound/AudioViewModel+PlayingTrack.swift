import Foundation

// MARK: - AudioViewModel + the current library song (S10.8 E2)

extension AudioViewModel {
    /// The library id of the queue's current song — the row the Library lists mark as playing (Songs,
    /// the album, artist and genre pages), as the queue marks its own. It keeps the mark while
    /// PAUSED: the row's equalizer just stands still (`isPlaying` drives the bars). Nil with no
    /// current song, and for a file opened from outside the library.
    var playingTrackID: Int64? {
        guard let index = selectedTrackIndex, index < queue.count else { return nil }
        return queue[index].file.trackID
    }
}
