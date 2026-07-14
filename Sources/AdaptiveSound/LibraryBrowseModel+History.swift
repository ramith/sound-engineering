import Foundation
import LibraryStore

// MARK: - LibraryBrowseModel Recently-Played (frecency) loader (S10.6)

extension LibraryBrowseModel {
    /// Load the Recently-Played (frecency) rows. Mirrors `loadSongs`' epoch / `isStoreReady` guard;
    /// the DAO returns tracks played at least once, already frecency-ordered. Empty ⇒ the tab shows
    /// its empty state ("nothing finished yet") — no firstRun/roots distinction is needed here.
    func loadHistory() async {
        guard let store else {
            historyState = .loading // store still building; the tab reloads on `isStoreReady`
            return
        }
        historyLoadEpoch &+= 1
        let epoch = historyLoadEpoch
        do {
            let loaded = try await store.frecencyTracksDisplay()
            guard epoch == historyLoadEpoch else { return } // a newer load superseded this one
            history = loaded
            historyState = loaded.isEmpty ? .empty : .loaded
        } catch {
            guard epoch == historyLoadEpoch else { return }
            historyState = .failed(error.localizedDescription)
        }
    }
}
