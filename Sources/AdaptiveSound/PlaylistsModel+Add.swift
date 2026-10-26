import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore

// MARK: - PlaylistsModel + adding songs and loose files (US-PLIST-02; R1.1-B — files from outside the library)

/// The one add path for a playlist — library songs by id and files from outside the library — split from
/// `PlaylistsModel` for file length. `addTracks` / `createPlaylist(withTracks:)` (the main file) are the
/// library-songs-only forms of these.
extension PlaylistsModel {
    /// A playlist made with songs in it: its id, and how many songs went in.
    struct NewPlaylist: Equatable {
        let id: Int64
        let added: Int
    }

    /// What an append did: how many entries went in — every one counted, even when a later write failed
    /// (each run of library songs and each loose file is its own write) — and the failure, if one stopped it.
    struct AppendOutcome: Sendable {
        let added: Int
        let failure: (any Error)?
    }

    /// Append `items` — library songs by id, and files from outside the library (R1.1-B, US-PLIST-02:
    /// each becomes a song in no music folder, `LibraryStore.addLooseFileToPlaylist`) — to a playlist, in
    /// order, the selection de-duplicated. Every add is a REFERENCE-add: nothing on disk moves. A file the
    /// library holds already (a library song, or one added before) is added as that song. Reloads the tree
    /// and the open detail if it's the target; a loose file's tags are read in the background. Returns the
    /// number actually appended (for the toast) — the ones before a failure too (review N3).
    @discardableResult
    func add(_ items: [PlaylistAddItem], toPlaylist playlistID: Int64) async -> Int {
        let ordered = PlaylistAddDecision.itemsToAdd(items)
        guard let store, !ordered.isEmpty else { return 0 }
        let outcome = await Self.append(ordered, toPlaylist: playlistID, in: store)
        if let failure = outcome.failure {
            fail("Couldn’t add to \(quotedName(of: playlistID)): \(failure.localizedDescription)")
        }
        await loadTree()
        if openPlaylistID == playlistID {
            await loadDetail(id: playlistID)
        }
        if ordered.contains(where: \.isFile) {
            library.readPendingTags()
        }
        return outcome.added
    }

    /// Create a new untitled playlist holding `items` (library songs and loose files) and reload. Returns
    /// the playlist and how many songs went in (fewer than asked when a write failed, said in the notice) —
    /// nil when no playlist was made.
    @discardableResult
    func createPlaylist(with items: [PlaylistAddItem]) async -> NewPlaylist? {
        guard let store else { return nil }
        let ordered = PlaylistAddDecision.itemsToAdd(items)
        let id: Int64
        do {
            id = try await store.createUntitledPlaylist()
        } catch {
            fail("Couldn’t create the playlist: \(error.localizedDescription)")
            return nil
        }
        let outcome = await Self.append(ordered, toPlaylist: id, in: store)
        await loadTree() // a playlist created before its add failed still shows
        if let failure = outcome.failure {
            fail("Couldn’t add to the new playlist: \(failure.localizedDescription)")
        }
        if ordered.contains(where: \.isFile) {
            library.readPendingTags()
        }
        return NewPlaylist(id: id, added: outcome.added)
    }

    /// Append `items` to `playlistID` in order: each run of library songs in one write, each loose file in
    /// its own (the store's loose-file seam). A file that can't be read, or is a folder after all, is passed
    /// over. Off the main actor: a loose file is read from the disk (`makeScannedFile` — one resource fetch
    /// and one `lstat`), and 300 files on a spun-down disk or a network share must not stall the window
    /// (review S2). Counts what went in before a failure stopped it (review N3).
    @concurrent
    private nonisolated static func append(_ items: [PlaylistAddItem], toPlaylist playlistID: Int64,
                                           in store: LibraryStore) async -> AppendOutcome {
        var added = 0
        var run: [Int64] = []
        func flush() async throws {
            guard !run.isEmpty else { return }
            added += try await store.appendEntries(playlistID: playlistID, trackIDs: run).count
            run = []
        }
        do {
            for item in items {
                switch item {
                case let .track(id):
                    run.append(id)
                case let .file(url):
                    try await flush()
                    guard let file = LibraryScanner.makeScannedFile(fileURL: url,
                                                                    root: url.deletingLastPathComponent())
                    else { continue }
                    _ = try await store.addLooseFileToPlaylist(file, playlistID: playlistID)
                    added += 1
                }
            }
            try await flush()
            return AppendOutcome(added: added, failure: nil)
        } catch {
            return AppendOutcome(added: added, failure: error)
        }
    }
}
