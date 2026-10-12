import Foundation
import LibraryStore

// MARK: - LibraryBrowseModel + play actions

/// The browse Play verbs, delegating to `AudioViewModel`'s queue verbs (converting
/// `LibraryTrackDisplay → AudioFile` at this seam). Split into a same-type extension for file
/// length, like `+Facets` / `+History` / `+Sidebar`. A whole album, artist or genre (a browse tile)
/// plays through `+Facets`' `playFacet` / `playFacetNext` / `appendFacet`.
///
/// Every Library play that REPLACES the queue is undoable (S10.8 E review 18) — a page's Play and
/// Shuffle, a row's double-click, Return and menu Play, a tile's Play — through the queue's restore
/// point (`AudioViewModel.playNowWithUndo` / `shufflePlay`), and offers the undo on the Library card.
@MainActor
extension LibraryBrowseModel {
    /// Replace the queue with these songs and play from `index` — undoably: a page's Play (from the
    /// top), and a row's double-click, Return or menu Play (the page from that song on, decision 11).
    func play(_ tracks: [LibraryTrackDisplay], startAt index: Int) {
        let files = tracks.map(AudioFile.init)
        guard !files.isEmpty else { return }
        audio.playNowWithUndo(files, startAt: index)
        offerQueueRestore()
    }

    /// After a queue replace: "Queue replaced · Restore previous queue" on the Library card
    /// (`QueueRestoreToast`), while there is a queue to restore. The playlist page's plays raise it
    /// too.
    func offerQueueRestore() {
        if audio.canRestorePreviousQueue {
            restoreToast.show("Queue replaced")
        }
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
