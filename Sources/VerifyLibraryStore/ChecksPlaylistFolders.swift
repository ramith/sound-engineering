// ChecksPlaylistFolders — S10.3 playlist-FOLDER DAO checks (schema v5). Same idiom as
// ChecksPlaylists (Bool return, numbered PASS/FAIL, temp DBs). Registered via
// playlistFolderCheckCases() in main.swift.

import Foundation
import LibraryStore

// MARK: - Registration

func playlistFolderCheckCases() -> [CheckCase] {
    [
        CheckCase(label: "pl-folder-crud", run: checkFolderCRUD),
        CheckCase(label: "pl-folder-reparent-cycle-reject", run: checkFolderReparentCycle),
        CheckCase(label: "pl-folder-cascade-delete-restore", run: checkFolderCascadeDeleteRestore),
        CheckCase(label: "pl-folder-restore-conflict-rolls-back", run: checkFolderRestoreConflictRollsBack),
        CheckCase(label: "pl-set-playlist-folder-rejects", run: checkSetPlaylistFolderRejects),
        CheckCase(label: "pl-folder-edge-cases", run: checkFolderEdgeCases),
    ]
}

// MARK: - Checks

/// pl-folder-crud: create root + nested folders; parentage + rename; missing-parent rejected.
func checkFolderCRUD(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let jazz = try await store.createFolder(name: "Jazz", parentID: nil)
        let bebop = try await store.createFolder(name: "Bebop", parentID: jazz)
        let all = try await store.folders()
        guard let jazzRow = all.first(where: { $0.id == jazz }), jazzRow.parentID == nil,
              let bebopRow = all.first(where: { $0.id == bebop }), bebopRow.parentID == jazz else {
            printFail(number, "folder parentage wrong: \(all.map { ($0.id, $0.parentID as Any) })"); return false
        }
        try await store.renameFolder(id: jazz, to: "Jazz & Blues")
        guard try await store.folders().first(where: { $0.id == jazz })?.name == "Jazz & Blues" else {
            printFail(number, "folder rename not reflected"); return false
        }
        var missingParentRejected = false
        do {
            _ = try await store.createFolder(name: "Orphan", parentID: 999_999)
        } catch PlaylistMutationError.notFound {
            missingParentRejected = true
        }
        guard missingParentRejected else {
            printFail(number, "createFolder under a missing parent not rejected"); return false
        }
        printPass(number, "folder CRUD: root + nested create, parentage correct, rename works, missing-parent rejected")
        return true
    } catch { printFail(number, "pl-folder-crud threw: \(error)"); return false }
}

/// pl-folder-reparent-cycle-reject: a folder cannot become its own ancestor; a valid move works.
func checkFolderReparentCycle(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let top = try await store.createFolder(name: "A", parentID: nil)
        let mid = try await store.createFolder(name: "B", parentID: top)
        let leaf = try await store.createFolder(name: "C", parentID: mid)
        // `top` under `leaf` would create a cycle (`leaf` is a descendant of `top`) → reject.
        var cycleRejected = false
        do {
            try await store.reparentFolder(id: top, newParentID: leaf)
        } catch PlaylistMutationError.wouldCreateCycle {
            cycleRejected = true
        }
        // `top` under itself → reject.
        var selfRejected = false
        do {
            try await store.reparentFolder(id: top, newParentID: top)
        } catch PlaylistMutationError.wouldCreateCycle {
            selfRejected = true
        }
        guard cycleRejected, selfRejected else {
            printFail(number, "cycle not rejected (descendant=\(cycleRejected) self=\(selfRejected))"); return false
        }
        // `leaf` under `top` is valid (`top` is NOT in `leaf`'s subtree).
        try await store.reparentFolder(id: leaf, newParentID: top)
        guard try await store.folders().first(where: { $0.id == leaf })?.parentID == top else {
            printFail(number, "valid reparent (leaf under top) not reflected"); return false
        }
        printPass(number, "reparent cycle-guard: self + descendant moves rejected, a valid move succeeds")
        return true
    } catch { printFail(number, "pl-folder-reparent-cycle-reject threw: \(error)"); return false }
}

/// pl-folder-cascade-delete-restore: deleting a folder CASCADEs its subtree (subfolders + playlists
/// + entries); the returned snapshot restores it verbatim (ids + entry order preserved) — the undo.
func checkFolderCascadeDeleteRestore(number: Int, url: URL) async -> Bool {
    do {
        let seeded = try await seedTracks(url, root: "/M/FD",
                                          paths: ["/M/FD/a.flac", "/M/FD/b.flac"])
        let store = seeded.store
        let t = seeded.trackIDs
        let folder = try await store.createFolder(name: "F", parentID: nil)
        let sub = try await store.createFolder(name: "Sub", parentID: folder)
        let p1 = try await store.createPlaylist(name: "P1")
        try await store.setPlaylistFolder(playlistID: p1, folderID: folder)
        _ = try await store.appendEntry(playlistID: p1, trackID: t[0])
        let p2 = try await store.createPlaylist(name: "P2")
        try await store.setPlaylistFolder(playlistID: p2, folderID: sub)
        _ = try await store.appendEntries(playlistID: p2, trackIDs: t)

        let snapshot = try await store.deleteFolder(id: folder)
        // Everything under `folder` is gone (cascade).
        let foldersGone = try await store.folders().allSatisfy { $0.id != folder && $0.id != sub }
        guard foldersGone,
              try await store.playlist(id: p1) == nil, try await store.playlist(id: p2) == nil else {
            printFail(number, "cascade delete left folder/playlist rows behind"); return false
        }
        guard snapshot.folders.count == 2, snapshot.playlists.count == 2, snapshot.entries.count == 3 else {
            printFail(number, "snapshot wrong (folders=\(snapshot.folders.count) "
                + "playlists=\(snapshot.playlists.count) entries=\(snapshot.entries.count))"); return false
        }
        // Undo: restore the subtree verbatim.
        try await store.restoreFolderSubtree(snapshot)
        let restored = try await store.folders()
        guard restored.first(where: { $0.id == folder })?.parentID == nil,
              restored.first(where: { $0.id == sub })?.parentID == folder,
              try await store.playlist(id: p1) != nil, try await store.playlist(id: p2) != nil,
              try await store.entries(inPlaylist: p1).map(\.trackID) == [t[0]],
              try await store.entries(inPlaylist: p2).map(\.trackID) == t else {
            printFail(number, "restore did not reinstate the subtree verbatim"); return false
        }
        printPass(number, "folder delete CASCADEs the subtree; the snapshot restores it verbatim (undo) — "
            + "ids + entry order preserved")
        return true
    } catch { printFail(number, "pl-folder-cascade-delete-restore threw: \(error)"); return false }
}

/// pl-folder-restore-conflict-rolls-back: if the world changed between delete and undo (a deleted
/// playlist's NAME is reused before restore), `restoreFolderSubtree` must THROW and leave the store
/// UNCHANGED — never a half-inserted subtree (the single-txn + deferred-FK contract; QA break-it #2).
func checkFolderRestoreConflictRollsBack(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let folder = try await store.createFolder(name: "F", parentID: nil)
        let p1 = try await store.createPlaylist(name: "Keeper")
        try await store.setPlaylistFolder(playlistID: p1, folderID: folder)
        let snapshot = try await store.deleteFolder(id: folder) // p1 + folder gone (cascade)
        // Reuse the deleted playlist's name on a NEW playlist → restore's INSERT must hit the
        // (NOCASE) unique index and roll the whole restore back.
        _ = try await store.createPlaylist(name: "keeper") // NOCASE collision with "Keeper"
        let foldersBefore = try await store.folders().map(\.id).sorted()
        let playlistsBefore = try await store.playlists().map(\.id).sorted()
        var threw = false
        do { try await store.restoreFolderSubtree(snapshot) } catch { threw = true }
        guard threw else { printFail(number, "restore did not throw on a name collision"); return false }
        let foldersAfter = try await store.folders().map(\.id).sorted()
        let playlistsAfter = try await store.playlists().map(\.id).sorted()
        guard foldersAfter == foldersBefore, playlistsAfter == playlistsBefore else {
            printFail(number, "restore left PARTIAL state after a rolled-back conflict "
                + "(folders \(foldersBefore)->\(foldersAfter), playlists \(playlistsBefore)->\(playlistsAfter))")
            return false
        }
        printPass(number, "restore THROWS + rolls back cleanly on a NOCASE name collision — no partial subtree")
        return true
    } catch { printFail(number, "pl-folder-restore-conflict-rolls-back threw: \(error)"); return false }
}

/// pl-set-playlist-folder-rejects: `setPlaylistFolder` rejects the built-in "current" playlist
/// (`.builtinImmutable`) and a missing playlist / missing folder (`.notFound`) — not a silent no-op.
func checkSetPlaylistFolderRejects(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let builtinID = try await store.bootstrapBuiltinCurrentPlaylist()
        let folder = try await store.createFolder(name: "F", parentID: nil)
        var builtinRejected = false
        do {
            try await store.setPlaylistFolder(playlistID: builtinID, folderID: folder)
        } catch PlaylistMutationError.builtinImmutable {
            builtinRejected = true
        }
        var missingPlaylist = false
        do {
            try await store.setPlaylistFolder(playlistID: 999_999, folderID: folder)
        } catch PlaylistMutationError.notFound {
            missingPlaylist = true
        }
        let p1 = try await store.createPlaylist(name: "P1")
        var missingFolder = false
        do {
            try await store.setPlaylistFolder(playlistID: p1, folderID: 999_999)
        } catch PlaylistMutationError.notFound {
            missingFolder = true
        }
        guard builtinRejected, missingPlaylist, missingFolder else {
            printFail(number, "setPlaylistFolder guards wrong (builtin=\(builtinRejected) "
                + "missingPlaylist=\(missingPlaylist) missingFolder=\(missingFolder))")
            return false
        }
        printPass(number, "setPlaylistFolder rejects the built-in (.builtinImmutable) + missing "
            + "playlist/folder (.notFound)")
        return true
    } catch { printFail(number, "pl-set-playlist-folder-rejects threw: \(error)"); return false }
}

/// pl-folder-edge-cases: empty-folder delete+restore; reparent-to-nil (back to root); and a deep
/// (40-level) chain delete → cascade snapshot → verbatim restore (recursion + ordering under depth).
func checkFolderEdgeCases(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        // Empty-folder delete + restore.
        let empty = try await store.createFolder(name: "Empty", parentID: nil)
        let emptySnap = try await store.deleteFolder(id: empty)
        guard try await store.folders().first(where: { $0.id == empty }) == nil else {
            printFail(number, "empty folder not deleted"); return false
        }
        try await store.restoreFolderSubtree(emptySnap)
        guard try await store.folders().contains(where: { $0.id == empty }) else {
            printFail(number, "empty folder not restored"); return false
        }
        // reparent-to-nil: a nested folder moves back to root.
        let parent = try await store.createFolder(name: "P", parentID: nil)
        let child = try await store.createFolder(name: "C", parentID: parent)
        try await store.reparentFolder(id: child, newParentID: nil)
        guard try await store.folders().first(where: { $0.id == child })?.parentID == nil else {
            printFail(number, "reparent-to-nil did not move to root"); return false
        }
        // Deep chain: 40 nested levels, delete the root → whole chain cascades + restores.
        var parentID: Int64?
        var deepIDs: [Int64] = []
        for level in 0 ..< 40 {
            let id = try await store.createFolder(name: "L\(level)", parentID: parentID)
            deepIDs.append(id); parentID = id
        }
        let deepSnap = try await store.deleteFolder(id: deepIDs[0])
        guard deepSnap.folders.count == 40 else {
            printFail(number, "deep-nest snapshot has \(deepSnap.folders.count) folders, expected 40"); return false
        }
        try await store.restoreFolderSubtree(deepSnap)
        let restored = try await store.folders()
        guard deepIDs.allSatisfy({ id in restored.contains(where: { $0.id == id }) }) else {
            printFail(number, "deep-nest restore incomplete"); return false
        }
        printPass(number, "folder edge cases: empty delete+restore, reparent-to-nil, 40-level cascade+restore")
        return true
    } catch { printFail(number, "pl-folder-edge-cases threw: \(error)"); return false }
}
