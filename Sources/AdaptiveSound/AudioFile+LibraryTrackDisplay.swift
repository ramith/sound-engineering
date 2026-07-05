import Foundation
import LibraryStore

// MARK: - AudioFile ← LibraryTrackDisplay (S9-Q2 queue adapter)

extension AudioFile {
    /// Adapt a library track into the play-queue's `AudioFile` shape.
    ///
    /// `name = track.title` — the projection's `title` already falls back to the filename
    /// when the tag title is absent (LibraryTrackDisplay §), so a queued library track
    /// shows its tag title in Now Playing rather than the raw filename (final-gate #8).
    /// `relativePath` is empty: a library track has no meaningful scan-folder-relative path.
    /// The existing Now-Playing queue row (`PlaylistItemRow`) renders `relativePath` as its
    /// second line, so a library-queued track shows a blank subtitle there until that row
    /// guards the empty case / shows artist·album (S9.4+ shared TrackRow). `AudioFile.id ==
    /// absoluteURL` carries the identity playback needs; the durable `tracks.id` is dropped
    /// (queue identity is the URL) — S10's play-count write-back will need a `url → id`
    /// lookup (flagged seam). Kept in its own file so the base `AudioFile` model stays
    /// store-agnostic (LibraryStore can't see AudioFile).
    init(_ track: LibraryTrackDisplay) {
        self.init(
            name: track.title,
            relativePath: "",
            absoluteURL: track.url,
            format: track.format,
            durationSeconds: track.durationSeconds
        )
    }
}
