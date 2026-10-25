import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore

// MARK: - PlaylistsModel + adding songs and loose files (US-PLIST-02; R1.1-B — files from outside the library)

/// The one add path for a playlist — library songs by id and files from outside the library — split from
/// `PlaylistsModel` for file length. `addTracks` / `createPlaylist(withTracks:)` (the main file) are the
/// library-songs-only forms of these.
extension PlaylistsModel {
    /// Append `items` — library songs by id, and files from outside the library (R1.1-B, US-PLIST-02:
    /// each becomes a song in no music folder, `LibraryStore.addLooseFileToPlaylist`) — to a playlist, in
    /// order, the selection de-duplicated. Every add is a REFERENCE-add: nothing on disk moves. A file the
    /// library holds already (a library song, or one added before) is added as that song. Reloads the tree
    /// and the open detail if it's the target; a loose file's tags are read in the background. Returns
    /// the number appended (for the toast).
    @discardableResult
    func add(_ items: [PlaylistAddItem], toPlaylist playlistID: Int64) async -> Int {
        let ordered = PlaylistAddDecision.itemsToAdd(items)
        guard let store, !ordered.isEmpty else { return 0 }
        var added = 0
        do {
            added = try await Self.append(ordered, toPlaylist: playlistID, in: store)
        } catch {
            fail("Couldn’t add to \(quotedName(of: playlistID)): \(error.localizedDescription)")
        }
        await loadTree()
        if openPlaylistID == playlistID {
            await loadDetail(id: playlistID)
        }
        if ordered.contains(where: \.isFile) {
            library.readPendingTags()
        }
        return added
    }

    /// Create a new untitled playlist holding `items` (library songs and loose files) and reload.
    @discardableResult
    func createPlaylist(with items: [PlaylistAddItem]) async -> Int64? {
        guard let store else { return nil }
        let ordered = PlaylistAddDecision.itemsToAdd(items)
        do {
            let id = try await store.createUntitledPlaylist()
            _ = try await Self.append(ordered, toPlaylist: id, in: store)
            await loadTree()
            if ordered.contains(where: \.isFile) {
                library.readPendingTags()
            }
            return id
        } catch {
            await loadTree() // a playlist created before its add failed still shows
            fail("Couldn’t create the playlist: \(error.localizedDescription)")
            return nil
        }
    }

    /// Append `items` to `playlistID` in order: each run of library songs in one write, each loose file in
    /// its own (the store's loose-file seam). A file that can't be read is passed over. Returns the count.
    private static func append(_ items: [PlaylistAddItem], toPlaylist playlistID: Int64,
                               in store: LibraryStore) async throws -> Int {
        var added = 0
        var run: [Int64] = []
        func flush() async throws {
            guard !run.isEmpty else { return }
            added += try await store.appendEntries(playlistID: playlistID, trackIDs: run).count
            run = []
        }
        for item in items {
            switch item {
            case let .track(id):
                run.append(id)
            case let .file(url):
                try await flush()
                guard let file = LibraryScanner.makeScannedFile(fileURL: url, root: url.deletingLastPathComponent())
                else { continue }
                _ = try await store.addLooseFileToPlaylist(file, playlistID: playlistID)
                added += 1
            }
        }
        try await flush()
        return added
    }
}
