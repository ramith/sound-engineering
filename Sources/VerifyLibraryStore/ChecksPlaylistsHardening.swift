// ChecksPlaylistsHardening — S10.1 break-it fix checks (D1-D6) + S10.2 queue-mirror
// store-op checks. Split out of ChecksPlaylists.swift to keep both files <500 lines.
// Same VerifyAUGraph idiom; registered via playlistSpineCheckCases() in ChecksPlaylists.swift.

import Foundation
import LibraryStore

/// pl-reorder-partial (D1): a PARTIAL reorder list renumbers the WHOLE playlist — omitted entries
/// keep their relative order and positions stay collision-free (a foreign id is ignored).
func checkPlaylistReorderPartial(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/RP", paths: ["/M/RP/a.flac", "/M/RP/b.flac", "/M/RP/c.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "RP")
        let entryIDs = try await store.appendEntries(playlistID: pid, trackIDs: t)
        try await store.reorderPlaylist(id: pid, entryIDsInOrder: [entryIDs[2], 999_999])
        let after = try await store.entries(inPlaylist: pid)
        guard after.map(\.id) == [entryIDs[2], entryIDs[0], entryIDs[1]] else {
            printFail(number, "partial reorder scrambled order: \(after.map(\.id))"); return false
        }
        guard Set(after.map(\.position)).count == after.count else {
            printFail(number, "partial reorder left colliding positions: \(after.map(\.position))"); return false
        }
        printPass(number, "partial/foreign reorder renumbers the whole playlist — no position collision (D1)")
        return true
    } catch { printFail(number, "pl-reorder-partial threw: \(error)"); return false }
}

/// pl-loose-add-existing (D2): adding a URL that is already a FOLDER track reuses the row — it does
/// NOT null its folder_id or create a duplicate.
func checkPlaylistLooseAddExisting(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/LE", paths: ["/M/LE/song.flac"])
        let store = seeded.store
        let rootID = seeded.rootID
        let t = seeded.trackIDs
        let tracksBefore = try await store.countRows(inTable: "tracks")
        let inFolderBefore = try await store.tracks(inFolder: rootID).count
        let pid = try await store.createPlaylist(name: "LE")
        let file = makeScanned(path: "/M/LE/song.flac", name: "song.flac")
        let result = try await store.addLooseFileToPlaylist(file, playlistID: pid)
        guard result.trackID == t[0],
              try await store.countRows(inTable: "tracks") == tracksBefore,
              try await store.tracks(inFolder: rootID).count == inFolderBefore,
              try await store.entries(inPlaylist: pid).map(\.trackID) == [t[0]] else {
            printFail(number, "loose-add of an existing folder track duplicated it or detached its folder (D2)")
            return false
        }
        printPass(number, "loose-add of an already-library track reuses the row (no dup, folder intact) (D2)")
        return true
    } catch { printFail(number, "pl-loose-add-existing threw: \(error)"); return false }
}

/// pl-remove-foreign-scoped (D3): removeEntry(ies) is playlist-scoped — a foreign entry id can't
/// delete from another playlist.
func checkPlaylistRemoveForeignScoped(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/RF", paths: ["/M/RF/a.flac", "/M/RF/b.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let plA = try await store.createPlaylist(name: "A")
        let plB = try await store.createPlaylist(name: "B")
        _ = try await store.appendEntry(playlistID: plA, trackID: t[0])
        let bEntry = try await store.appendEntry(playlistID: plB, trackID: t[1])
        try await store.removeEntries(ids: [bEntry], playlistID: plA)
        try await store.removeEntry(id: bEntry, playlistID: plA)
        guard try await store.entries(inPlaylist: plB).map(\.id) == [bEntry] else {
            printFail(number, "DATA-LOSS: a foreign entry id deleted from another playlist (D3)"); return false
        }
        printPass(number, "removeEntry(ies) is playlist-scoped — a foreign id can't delete elsewhere (D3)")
        return true
    } catch { printFail(number, "pl-remove-foreign-scoped threw: \(error)"); return false }
}

/// pl-append-notfound (D4): appending to a nonexistent playlist throws typed .notFound, not raw GRDB.
func checkPlaylistAppendNotFound(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/NF", paths: ["/M/NF/a.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        var typed = false
        do {
            _ = try await store.appendEntry(playlistID: 999_999, trackID: t[0])
        } catch PlaylistMutationError.notFound {
            typed = true
        }
        guard typed else {
            printFail(number, "append to a nonexistent playlist did not throw typed .notFound (D4)"); return false
        }
        printPass(number, "append to a nonexistent playlist throws typed .notFound (D4)")
        return true
    } catch { printFail(number, "pl-append-notfound threw: \(error)"); return false }
}

/// pl-name-validation (D5/D6): empty / whitespace-only names and the reserved 'current' (any case)
/// are rejected with .invalidName.
func checkPlaylistNameValidation(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        for bad in ["", "   ", "current", "Current", "CURRENT"] {
            var rejected = false
            do {
                _ = try await store.createPlaylist(name: bad)
            } catch PlaylistMutationError.invalidName {
                rejected = true
            }
            guard rejected else {
                printFail(number, "invalid/reserved name \"\(bad)\" was accepted (D5/D6)"); return false
            }
        }
        printPass(number, "empty/whitespace + reserved 'current' (any case) rejected with .invalidName (D5/D6)")
        return true
    } catch { printFail(number, "pl-name-validation threw: \(error)"); return false }
}

/// pl-replace-entries (S10.2 snapshot primitive): replaceEntries overwrites contents in order with
/// dense positions; an empty snapshot clears; a track may repeat.
func checkPlaylistReplaceEntries(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(
            url, root: "/M/RPL", paths: ["/M/RPL/a.flac", "/M/RPL/b.flac", "/M/RPL/c.flac"]
        )
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "RPL")
        _ = try await store.appendEntries(playlistID: pid, trackIDs: [t[0], t[1]])
        // Snapshot to a new order incl. a duplicate.
        try await store.replaceEntries(playlistID: pid, trackIDs: [t[2], t[0], t[0]])
        let after = try await store.entries(inPlaylist: pid)
        guard after.map(\.trackID) == [t[2], t[0], t[0]], after.map(\.position) == [0, 1, 2] else {
            printFail(number, "replaceEntries wrong contents/positions: \(after.map { ($0.trackID, $0.position) })")
            return false
        }
        try await store.replaceEntries(playlistID: pid, trackIDs: [])
        guard try await store.entries(inPlaylist: pid).isEmpty else {
            printFail(number, "empty replaceEntries did not clear"); return false
        }
        printPass(number, "replaceEntries: snapshot overwrite in order (dense positions, dup ok); empty clears")
        return true
    } catch { printFail(number, "pl-replace-entries threw: \(error)"); return false }
}

/// pl-clear-entries: clearEntries empties one playlist without touching another.
func checkPlaylistClearEntries(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/CLR", paths: ["/M/CLR/a.flac", "/M/CLR/b.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let plA = try await store.createPlaylist(name: "CA")
        let plB = try await store.createPlaylist(name: "CB")
        _ = try await store.appendEntries(playlistID: plA, trackIDs: t)
        _ = try await store.appendEntry(playlistID: plB, trackID: t[0])
        try await store.clearEntries(playlistID: plA)
        guard try await store.entries(inPlaylist: plA).isEmpty,
              try await store.entries(inPlaylist: plB).count == 1 else {
            printFail(number, "clearEntries emptied the wrong playlist or left rows"); return false
        }
        printPass(number, "clearEntries empties only the target playlist")
        return true
    } catch { printFail(number, "pl-clear-entries threw: \(error)"); return false }
}

/// pl-playcount-by-id (S10.2): the durable-id incrementPlayCount overload accumulates + stamps,
/// and a nonexistent id is a silent no-op.
func checkPlaylistPlayCountByID(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/PC", paths: ["/M/PC/a.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        try await store.incrementPlayCount(id: t[0], playedAt: 1000)
        try await store.incrementPlayCount(id: t[0], playedAt: 2000)
        guard let state = try await store.userState(trackID: t[0]), state.playCount == 2 else {
            printFail(number, "incrementPlayCount(id:) did not accumulate to 2"); return false
        }
        try await store.incrementPlayCount(id: 999_999, playedAt: 3000) // silent no-op
        guard try await store.userState(trackID: t[0])?.playCount == 2 else {
            printFail(number, "nonexistent-id play-count was not a no-op"); return false
        }
        printPass(number, "incrementPlayCount(id:) accumulates + stamps; absent id is a silent no-op")
        return true
    } catch { printFail(number, "pl-playcount-by-id threw: \(error)"); return false }
}
