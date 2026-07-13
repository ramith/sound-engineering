// ChecksPlaylists — S10.1 playlist/queue spine checks. Same VerifyAUGraph idiom
// (Bool return, numbered PASS/FAIL, temp DBs under test-data/). Drives the real
// LibraryStore playlist DAO + the Gate-1 (SEQ-1) closure. Registered via
// playlistSpineCheckCases() in main.swift's allCheckCases().

import Foundation
import LibraryStore

// MARK: - Registration

func playlistSpineCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "pl-crud", run: checkPlaylistCRUD),
        CheckCase(label: "pl-builtin-protected", run: checkPlaylistBuiltinProtected),
        CheckCase(label: "pl-ordered-membership", run: checkPlaylistOrderedMembership),
        CheckCase(label: "pl-same-track-twice", run: checkPlaylistSameTrackTwice),
        CheckCase(label: "pl-reorder", run: checkPlaylistReorder),
        CheckCase(label: "pl-insert-at", run: checkPlaylistInsertAt),
        CheckCase(label: "pl-remove-entries", run: checkPlaylistRemoveEntries),
        CheckCase(label: "pl-reorder-partial", run: checkPlaylistReorderPartial),
        CheckCase(label: "pl-loose-add-existing", run: checkPlaylistLooseAddExisting),
        CheckCase(label: "pl-remove-foreign-scoped", run: checkPlaylistRemoveForeignScoped),
        CheckCase(label: "pl-append-notfound", run: checkPlaylistAppendNotFound),
        CheckCase(label: "pl-name-validation", run: checkPlaylistNameValidation),
        CheckCase(label: "pl-untitled-lowest-unused", run: checkPlaylistUntitledNaming),
        CheckCase(label: "pl-dup-name-rejected", run: checkPlaylistDuplicateNameRejected),
        CheckCase(label: "pl-loose-add", run: checkPlaylistLooseAdd),
        CheckCase(label: "pl-gate1-referenced-kept", run: checkPlaylistGate1ReferencedKept),
        CheckCase(label: "pl-gate1-unreferenced-swept", run: checkPlaylistGate1UnreferencedSwept),
        CheckCase(label: "pl-file-gone-drop", run: checkPlaylistFileGoneDrop),
        CheckCase(label: "pl-persist-reopen", run: checkPlaylistPersistAcrossReopen),
    ]
}

// MARK: - Small helpers

/// A seeded fixture: the open store, its root folder id, and the seeded track ids.
private struct SeededTracks {
    let store: LibraryStore
    let rootID: Int64
    let trackIDs: [Int64]
}

/// Seed N tracks under a fresh root.
private func seedTracks(_ url: URL, root: String, paths: [String]) async throws -> SeededTracks {
    let store = try await LibraryStore(url: url, appBuild: "verify")
    let generation = try await store.beginScanGeneration()
    let rootID = try await store.addRoot(URL(fileURLWithPath: root))
    let files = paths.map { makeScanned(path: $0, name: ($0 as NSString).lastPathComponent) }
    let ids = try await store.upsert(files, folderID: rootID, generation: generation)
    return SeededTracks(store: store, rootID: rootID, trackIDs: ids)
}

// MARK: - Checks

/// pl-crud: create → list → rename → delete; count tracks the changes.
func checkPlaylistCRUD(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // Fresh v3 store seeds exactly the built-in "current"; count starts at 1.
        let base = try await store.playlistCount()
        let id = try await store.createPlaylist(name: "Road Trip")
        guard try await store.playlistCount() == base + 1 else {
            printFail(number, "createPlaylist did not increment count"); return false
        }
        guard let made = try await store.playlist(id: id), made.name == "Road Trip", !made.isBuiltin,
              made.createdAt > 0, made.entryCount == 0 else {
            printFail(number, "created playlist not readable / wrong fields"); return false
        }
        try await store.renamePlaylist(id: id, to: "Road Trip 2024")
        guard try await store.playlist(id: id)?.name == "Road Trip 2024" else {
            printFail(number, "rename not reflected"); return false
        }
        try await store.deletePlaylist(id: id)
        guard try await store.playlist(id: id) == nil, try await store.playlistCount() == base else {
            printFail(number, "delete not reflected"); return false
        }
        printPass(number, "playlist CRUD: create/list/rename/delete round-trip, count correct")
        return true
    } catch { printFail(number, "pl-crud threw: \(error)"); return false }
}

/// pl-builtin-protected: exactly one built-in "current"; rename/delete rejected; bootstrap idempotent.
func checkPlaylistBuiltinProtected(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let currentID = try await store.currentPlaylistID()
        // Idempotent bootstrap returns the same id (single-builtin invariant).
        guard try await store.bootstrapBuiltinCurrentPlaylist() == currentID else {
            printFail(number, "bootstrap not idempotent"); return false
        }
        let builtins = try await store.playlists().filter(\.isBuiltin)
        guard builtins.count == 1, builtins[0].name == "current" else {
            printFail(number, "expected exactly one built-in 'current', got \(builtins.map(\.name))"); return false
        }
        // Rename rejected.
        var renameRejected = false
        do {
            try await store.renamePlaylist(id: currentID, to: "queue")
        } catch PlaylistMutationError.builtinImmutable {
            renameRejected = true
        }
        // Delete rejected.
        var deleteRejected = false
        do {
            try await store.deletePlaylist(id: currentID)
        } catch PlaylistMutationError.builtinImmutable {
            deleteRejected = true
        }
        guard renameRejected, deleteRejected else {
            printFail(number, "built-in rename/delete not rejected (rename=\(renameRejected) delete=\(deleteRejected))")
            return false
        }
        printPass(number, "built-in 'current' is singular, idempotent to bootstrap, rename/delete rejected")
        return true
    } catch { printFail(number, "pl-builtin-protected threw: \(error)"); return false }
}

/// pl-ordered-membership: append 3 → entries in position order referencing the right tracks.
func checkPlaylistOrderedMembership(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/OM", paths: ["/M/OM/a.flac", "/M/OM/b.flac", "/M/OM/c.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "OM")
        _ = try await store.appendEntries(playlistID: pid, trackIDs: t)
        let entries = try await store.entries(inPlaylist: pid)
        guard entries.map(\.trackID) == t else {
            printFail(number, "entry order \(entries.map(\.trackID)) != append order \(t)"); return false
        }
        guard entries.map(\.position) == entries.map(\.position).sorted() else {
            printFail(number, "positions not ascending"); return false
        }
        guard entries.allSatisfy({ $0.playlistID == pid && $0.addedAt > 0 }),
              try await store.playlist(id: pid)?.entryCount == t.count else {
            printFail(number, "entry playlistID/addedAt or playlist entryCount wrong"); return false
        }
        printPass(number, "ordered membership: appendEntries preserves order, positions ascending, entryCount matches")
        return true
    } catch { printFail(number, "pl-ordered-membership threw: \(error)"); return false }
}

/// pl-same-track-twice: the SAME track appended twice → two distinct entries (own id).
func checkPlaylistSameTrackTwice(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/ST", paths: ["/M/ST/a.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "ST")
        let e1 = try await store.appendEntry(playlistID: pid, trackID: t[0])
        let e2 = try await store.appendEntry(playlistID: pid, trackID: t[0])
        let entries = try await store.entries(inPlaylist: pid)
        guard entries.count == 2, e1 != e2,
              entries.allSatisfy({ $0.trackID == t[0] }),
              Set(entries.map(\.id)) == Set([e1, e2]) else {
            printFail(number, "same track twice not represented as two distinct entries"); return false
        }
        printPass(number, "same track appears twice as two distinct entries (own entry id)")
        return true
    } catch { printFail(number, "pl-same-track-twice threw: \(error)"); return false }
}

/// pl-reorder: reorder → resulting ORDER BY position sequence matches the requested order.
func checkPlaylistReorder(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/RE", paths: ["/M/RE/a.flac", "/M/RE/b.flac", "/M/RE/c.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "RE")
        var entryIDs: [Int64] = []
        for id in t {
            try entryIDs.append(await store.appendEntry(playlistID: pid, trackID: id))
        }
        // Reverse the order.
        let desired = Array(entryIDs.reversed())
        try await store.reorderPlaylist(id: pid, entryIDsInOrder: desired)
        let after = try await store.entries(inPlaylist: pid)
        guard after.map(\.id) == desired else {
            printFail(number, "reorder sequence \(after.map(\.id)) != desired \(desired)"); return false
        }
        printPass(number, "reorder: ORDER BY position sequence matches the requested order")
        return true
    } catch { printFail(number, "pl-reorder threw: \(error)"); return false }
}

/// pl-insert-at: insert at an ordinal index → correct resulting sequence.
func checkPlaylistInsertAt(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/IN", paths: ["/M/IN/a.flac", "/M/IN/b.flac", "/M/IN/c.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "IN")
        let e0 = try await store.appendEntry(playlistID: pid, trackID: t[0])
        let e1 = try await store.appendEntry(playlistID: pid, trackID: t[1])
        // Insert track c at index 1 → order [a, c, b].
        let eMid = try await store.insertEntry(playlistID: pid, trackID: t[2], at: 1)
        let after = try await store.entries(inPlaylist: pid)
        guard after.map(\.id) == [e0, eMid, e1], after.map(\.trackID) == [t[0], t[2], t[1]] else {
            printFail(number, "insert-at sequence wrong: \(after.map(\.trackID))"); return false
        }
        printPass(number, "insert-at: track spliced at the requested ordinal, order renumbered")
        return true
    } catch { printFail(number, "pl-insert-at threw: \(error)"); return false }
}

/// pl-remove-entries: removeEntry drops one (survivor order kept); removeEntries clears the rest.
func checkPlaylistRemoveEntries(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/RM", paths: ["/M/RM/a.flac", "/M/RM/b.flac", "/M/RM/c.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "RM")
        let entryIDs = try await store.appendEntries(playlistID: pid, trackIDs: t)
        try await store.removeEntry(id: entryIDs[1], playlistID: pid)
        guard try await store.entries(inPlaylist: pid).map(\.id) == [entryIDs[0], entryIDs[2]] else {
            printFail(number, "removeEntry left wrong survivors"); return false
        }
        try await store.removeEntries(ids: [entryIDs[0], entryIDs[2]], playlistID: pid)
        guard try await store.entries(inPlaylist: pid).isEmpty else {
            printFail(number, "removeEntries did not clear the playlist"); return false
        }
        printPass(number, "remove: removeEntry drops one (order preserved); removeEntries clears the rest")
        return true
    } catch { printFail(number, "pl-remove-entries threw: \(error)"); return false }
}

/// pl-untitled-lowest-unused: Apple-style default name; lowest-unused after a delete.
func checkPlaylistUntitledNaming(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let id1 = try await store.createUntitledPlaylist()
        let id2 = try await store.createUntitledPlaylist()
        let id3 = try await store.createUntitledPlaylist()
        guard try await store.playlist(id: id1)?.name == "New Playlist",
              try await store.playlist(id: id2)?.name == "New Playlist 2",
              try await store.playlist(id: id3)?.name == "New Playlist 3" else {
            printFail(number, "default naming not Apple-style"); return false
        }
        // Delete #2 → next untitled fills the lowest gap ("New Playlist 2").
        try await store.deletePlaylist(id: id2)
        let id4 = try await store.createUntitledPlaylist()
        guard try await store.playlist(id: id4)?.name == "New Playlist 2" else {
            printFail(number, "lowest-unused not reused after delete"); return false
        }
        printPass(number, "default name Apple-style ('New Playlist', 'New Playlist 2', …), lowest-unused reused")
        return true
    } catch { printFail(number, "pl-untitled-lowest-unused threw: \(error)"); return false }
}

/// pl-dup-name-rejected: create + rename to an existing user name → PlaylistNameConflict.
func checkPlaylistDuplicateNameRejected(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        _ = try await store.createPlaylist(name: "Rock")
        var createRejected = false
        do {
            _ = try await store.createPlaylist(name: "Rock")
        } catch let conflict as PlaylistNameConflict {
            createRejected = conflict.name == "Rock" && conflict.existingID > 0
        }
        let other = try await store.createPlaylist(name: "Jazz")
        var renameRejected = false
        do {
            try await store.renamePlaylist(id: other, to: "Rock")
        } catch is PlaylistNameConflict {
            renameRejected = true
        }
        guard createRejected, renameRejected else {
            printFail(number, "duplicate name not rejected (create=\(createRejected) rename=\(renameRejected))")
            return false
        }
        printPass(number, "duplicate user playlist name rejected on both create and rename")
        return true
    } catch { printFail(number, "pl-dup-name-rejected threw: \(error)"); return false }
}

/// pl-loose-add: add a non-library file to a playlist → a loose track row + an entry, no root needed.
func checkPlaylistLooseAdd(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let pid = try await store.createPlaylist(name: "Loose")
        let before = try await store.countRows(inTable: "tracks")
        let file = makeScanned(path: "/Elsewhere/loose.flac", name: "loose.flac")
        let result = try await store.addLooseFileToPlaylist(file, playlistID: pid)
        let entries = try await store.entries(inPlaylist: pid)
        guard try await store.countRows(inTable: "tracks") == before + 1,
              entries.count == 1, entries[0].trackID == result.trackID, entries[0].id == result.entryID else {
            printFail(number, "loose add did not create one track row + one entry"); return false
        }
        printPass(number, "loose-file add: created a loose track row + a playlist entry, atomically")
        return true
    } catch { printFail(number, "pl-loose-add threw: \(error)"); return false }
}

/// pl-gate1-referenced-kept: a playlist-referenced track SURVIVES removeRoot (detached to loose).
func checkPlaylistGate1ReferencedKept(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/G1", paths: ["/M/G1/keep.flac"])
        let store = seeded.store
        let rootID = seeded.rootID
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "G1")
        let entryID = try await store.appendEntry(playlistID: pid, trackID: t[0])
        let tracksBefore = try await store.countRows(inTable: "tracks")
        try await store.removeRoot(id: rootID)
        // The referenced track must still exist and its entry survive.
        let entries = try await store.entries(inPlaylist: pid)
        guard try await store.countRows(inTable: "tracks") == tracksBefore,
              entries.count == 1, entries[0].id == entryID, entries[0].trackID == t[0] else {
            printFail(number, "GATE-1 VIOLATION: playlist-referenced track deleted by removeRoot"); return false
        }
        printPass(number, "Gate-1: playlist-referenced track survives removeRoot (kept loose), entry intact")
        return true
    } catch { printFail(number, "pl-gate1-referenced-kept threw: \(error)"); return false }
}

/// pl-gate1-unreferenced-swept: an UNreferenced track in the same root IS deleted by removeRoot.
func checkPlaylistGate1UnreferencedSwept(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/G1U", paths: ["/M/G1U/keep.flac", "/M/G1U/drop.flac"])
        let store = seeded.store
        let rootID = seeded.rootID
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "G1U")
        _ = try await store.appendEntry(playlistID: pid, trackID: t[0]) // only 'keep' is referenced
        try await store.removeRoot(id: rootID)
        // 'keep' survives (referenced); 'drop' is deleted → exactly one track row remains.
        guard try await store.countRows(inTable: "tracks") == 1 else {
            printFail(number, "unreferenced track not swept (or referenced one lost) on removeRoot"); return false
        }
        printPass(number, "Gate-1 inverse: an unreferenced track in the removed root is deleted")
        return true
    } catch { printFail(number, "pl-gate1-unreferenced-swept threw: \(error)"); return false }
}

/// pl-file-gone-drop: a genuinely-deleted track CASCADE-drops from its playlists (§0.2).
func checkPlaylistFileGoneDrop(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/FG", paths: ["/M/FG/gone.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "FG")
        _ = try await store.appendEntry(playlistID: pid, trackID: t[0])
        guard try await store.entries(inPlaylist: pid).count == 1 else {
            printFail(number, "setup: entry not added"); return false
        }
        try await store.delete(id: t[0]) // file gone → explicit delete
        guard try await store.entries(inPlaylist: pid).isEmpty else {
            printFail(number, "deleted track's entry not CASCADE-dropped"); return false
        }
        printPass(number, "file-gone: a deleted track CASCADE-drops from its playlists (§0.2)")
        return true
    } catch { printFail(number, "pl-file-gone-drop threw: \(error)"); return false }
}

/// pl-persist-reopen: a playlist + entries survive dropping and reopening the store (no schema change).
func checkPlaylistPersistAcrossReopen(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/PR", paths: ["/M/PR/a.flac", "/M/PR/b.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let pid = try await store.createPlaylist(name: "Persisted")
        for id in t {
            _ = try await store.appendEntry(playlistID: pid, trackID: id)
        }
        // Reopen the same file (no schema change → no erase).
        let reopened = try await LibraryStore(url: url, appBuild: "verify")
        guard let again = try await reopened.playlists().first(where: { $0.name == "Persisted" }),
              try await reopened.entries(inPlaylist: again.id).map(\.trackID) == t else {
            printFail(number, "playlist/entries did not survive reopen"); return false
        }
        printPass(number, "persistence: playlist + ordered entries survive a store reopen (no schema change)")
        return true
    } catch { printFail(number, "pl-persist-reopen threw: \(error)"); return false }
}

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
