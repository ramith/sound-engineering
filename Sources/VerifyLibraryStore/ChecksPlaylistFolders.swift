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
