import Foundation
import LibraryStore

// MARK: - LibraryBrowseModel + play actions

/// The browse Play verbs, delegating to `AudioViewModel`'s queue verbs (converting
/// `LibraryTrackDisplay → AudioFile` at this seam). Split into a same-type extension for file
/// length, like `+Facets` / `+History` / `+Sidebar`. A whole album, artist or genre (a browse tile)
/// plays through `+Facets`' `playFacet` / `playFacetNext` / `appendFacet`.
@MainActor
extension LibraryBrowseModel {
    /// Play a specific set of already-loaded display tracks now (album-detail row tap).
    func play(_ tracks: [LibraryTrackDisplay], startAt index: Int) {
        let files = tracks.map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.playNow(files, startAt: index)
    }

    func playNext(_ tracks: [LibraryTrackDisplay]) {
        guard !tracks.isEmpty else { return } // empty selection → nothing submitted, no toast
        showQueueToast(.playNext, added: audio.playNext(tracks.map(AudioFile.init)))
    }

    func append(_ tracks: [LibraryTrackDisplay]) {
        guard !tracks.isEmpty else { return } // empty selection → nothing submitted, no toast
        showQueueToast(.addToQueue, added: audio.appendToQueue(tracks.map(AudioFile.init)))
    }

    /// Insert a single track right after the current one and jump to play it NOW (Songs-list
    /// double-click / Return / single-row "Play"), preserving the rest of the existing queue.
    /// Converts `LibraryTrackDisplay → AudioFile` at this seam (like `play`/`playNext`/`append`)
    /// and delegates to `AudioViewModel.playTrackNextNow`.
    func playTrackNextNow(_ track: LibraryTrackDisplay) {
        audio.playTrackNextNow(AudioFile(track))
    }
}
