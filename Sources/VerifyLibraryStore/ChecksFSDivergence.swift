// ChecksFSDivergence — case F (filesystem divergence, FOUNDER REQUIREMENT §6-F).
//
// The store is a rebuildable CACHE of filesystem state, never assumed consistent
// with it (design §2a). These cases prove the S8.1 primitives that make that robust:
//   FS-1  a row whose url points at a non-existent/changed path is still queryable
//         (the store makes NO FS check on read and never crashes).
//   FS-2  the classify + orphan-detection primitives (last_seen_scan < gen) — the
//         reconciliation building blocks S8.4 uses.
//   FS-3  moveTrack + loose-file adoption (ON CONFLICT DO UPDATE) leave EXACTLY one
//         row (a file re-appearing at a new path while the app was closed does not
//         duplicate).
//   FS-4  a loose track (folder NULL) SURVIVES an orphan sweep of an unrelated root
//         AND removeRoot of an unrelated root.

import Foundation
import LibraryStore

// MARK: - F — filesystem divergence

func checkFilesystemDivergence(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")

        guard try await checkDivergedRowStillQueryable(store, number: number) else { return false }
        guard try await checkClassifyAndOrphanPrimitives(store, number: number) else { return false }
        guard try await checkNoDuplicateOnReappear(store, number: number) else { return false }
        guard try await checkLooseSurvivesUnrelatedReconcile(store, number: number) else { return false }

        printPass(number, "filesystem divergence: FS-1 diverged-path row still queryable (no FS check); "
            + "FS-2 classify + orphan (last_seen_scan<gen) primitives correct; FS-3 move/re-adopt leaves "
            + "1 row; FS-4 loose track survives an unrelated root's sweep AND removeRoot")
        return true
    } catch {
        printFail(number, "filesystem divergence threw: \(error)"); return false
    }
}

/// FS-1: a track whose url points at a path that does NOT exist on disk (and is not
/// even a real path) is still fully queryable — the store never touches the FS on a
/// read, so a store that diverged while the app was closed does not crash or hide rows.
private func checkDivergedRowStillQueryable(_ store: LibraryStore, number: Int) async throws -> Bool {
    let folderID = try await store.addRoot(URL(fileURLWithPath: "/Nonexistent/Volume/Ghost"))
    let generation = try await store.beginScanGeneration()
    // A path guaranteed absent from THIS machine's filesystem.
    let ghostPath = "/Nonexistent/Volume/Ghost/vanished-\(UUID().uuidString).flac"
    let ids = try await store.upsert(
        [makeScanned(path: ghostPath, name: "vanished")], folderID: folderID, generation: generation
    )
    guard let ghostID = ids.first else { printFail(number, "FS-1: seed failed"); return false }

    // Read by id, by url, and via allTracks — all must return the row, no FS access.
    guard let byID = try await store.track(id: ghostID) else {
        printFail(number, "FS-1: track(id:) did not return the diverged row"); return false
    }
    guard try await store.track(url: URL(fileURLWithPath: ghostPath)) != nil else {
        printFail(number, "FS-1: track(url:) did not return the diverged row"); return false
    }
    guard try await store.allTracks().contains(where: { $0.id == ghostID }) else {
        printFail(number, "FS-1: allTracks() omitted the diverged row"); return false
    }
    // Confirm the file genuinely does not exist (so this is a real divergence).
    guard !FileManager.default.fileExists(atPath: byID.url.path) else {
        printFail(number, "FS-1: the 'ghost' path unexpectedly exists on disk"); return false
    }
    return true
}

/// FS-2: the reconciliation primitives. A known path with a changed (size|mtime) →
/// .modified; an unseen path → .new; and a known path NOT re-seen in a new
/// generation is detectable as an orphan and swept (last_seen_scan < gen).
private func checkClassifyAndOrphanPrimitives(_ store: LibraryStore, number: Int) async throws -> Bool {
    let folderID = try await store.addRoot(URL(fileURLWithPath: "/Music/FS2"))
    let genOne = try await store.beginScanGeneration()
    let seen = makeScanned(path: "/Music/FS2/seen.flac", name: "seen", size: 100, mtime: 100)
    let stale = makeScanned(path: "/Music/FS2/stale.flac", name: "stale", size: 100, mtime: 100)
    _ = try await store.upsert([seen, stale], folderID: folderID, generation: genOne)

    // classify: changed signature → .modified; unseen → .new.
    let changed = makeScanned(path: "/Music/FS2/seen.flac", name: "seen", size: 200, mtime: 100)
    guard case .modified = try await store.classify(changed) else {
        printFail(number, "FS-2: changed-size path did not classify .modified"); return false
    }
    let unseen = makeScanned(path: "/Music/FS2/brand-new.flac", name: "brand-new")
    guard case .new = try await store.classify(unseen) else {
        printFail(number, "FS-2: unseen path did not classify .new"); return false
    }

    // Orphan sweep: a second generation re-sees only `seen`; `stale` (last_seen_scan
    // < new gen) is an orphan and is swept.
    let genTwo = try await store.beginScanGeneration()
    _ = try await store.upsert([seen], folderID: folderID, generation: genTwo)
    let swept = try await store.sweepOrphans(inFolders: [folderID], olderThan: genTwo)
    guard swept == 1 else {
        printFail(number, "FS-2: orphan sweep removed \(swept) rows, expected 1 (the stale row)"); return false
    }
    guard try await store.track(url: URL(fileURLWithPath: "/Music/FS2/stale.flac")) == nil,
          try await store.track(url: URL(fileURLWithPath: "/Music/FS2/seen.flac")) != nil else {
        printFail(number, "FS-2: orphan sweep removed the wrong row"); return false
    }
    return true
}

/// FS-3: a file that moved to a new path while the app was closed must NOT become a
/// duplicate. Two mechanisms leave exactly one row: (a) moveTrack (app-known move);
/// (b) loose-file adoption via ON CONFLICT DO UPDATE (re-scan finds the same url).
private func checkNoDuplicateOnReappear(_ store: LibraryStore, number: Int) async throws -> Bool {
    // (a) moveTrack: relocate a row's url; the store holds exactly one row for the
    // track and none at the old path.
    let folderID = try await store.addRoot(URL(fileURLWithPath: "/Music/FS3"))
    let gen = try await store.beginScanGeneration()
    let ids = try await store.upsert(
        [makeScanned(path: "/Music/FS3/orig.flac", name: "orig")], folderID: folderID, generation: gen
    )
    guard let trackID = ids.first else { printFail(number, "FS-3: move seed failed"); return false }
    let before = try await store.trackCount()
    try await store.moveTrack(
        id: trackID, newURL: URL(fileURLWithPath: "/Music/FS3/relocated.flac"),
        newFolderID: folderID, newRelativePath: "relocated.flac"
    )
    guard try await store.trackCount() == before else {
        printFail(number, "FS-3: moveTrack changed the row count (duplicate created)"); return false
    }

    // (b) loose-file re-adoption: a loose file is later found under a scan root; the
    // re-scan upserts the SAME url with a folder — ON CONFLICT DO UPDATE, one row.
    let looseFile = makeScanned(path: "/Music/FS3/adopt.flac", name: "adopt")
    let looseID = try await store.addLooseFile(looseFile)
    guard let loose = try await store.track(id: looseID), loose.folderID == nil else {
        printFail(number, "FS-3: loose file was not stored loose"); return false
    }
    let countAfterLoose = try await store.trackCount()
    let adoptGen = try await store.beginScanGeneration()
    let adoptedIDs = try await store.upsert([looseFile], folderID: folderID, generation: adoptGen)
    guard adoptedIDs.first == looseID else {
        printFail(number, "FS-3: adoption created a NEW row instead of updating the loose one"); return false
    }
    guard try await store.trackCount() == countAfterLoose else {
        printFail(number, "FS-3: adoption duplicated the row"); return false
    }
    guard let adopted = try await store.track(id: looseID), adopted.folderID == folderID else {
        printFail(number, "FS-3: adopted track did not gain the folder"); return false
    }
    return true
}

/// FS-4: a loose track (folder NULL) survives BOTH an orphan sweep of an unrelated
/// root AND removeRoot of an unrelated root — architect-verified invariants (loose
/// tracks are never folder-scoped, so unrelated reconciliation never touches them).
private func checkLooseSurvivesUnrelatedReconcile(_ store: LibraryStore, number: Int) async throws -> Bool {
    let looseID = try await store.addLooseFile(makeScanned(path: "/Music/FS4/loose.flac", name: "loose"))
    let unrelatedRoot = try await store.addRoot(URL(fileURLWithPath: "/Music/FS4-unrelated"))
    let gen = try await store.beginScanGeneration()
    _ = try await store.upsert(
        [makeScanned(path: "/Music/FS4-unrelated/x.flac", name: "x")],
        folderID: unrelatedRoot, generation: gen
    )

    // Sweep the unrelated root with a FUTURE generation (would sweep everything in
    // THAT folder) — the loose track (folder NULL) must be untouched.
    _ = try await store.sweepOrphans(inFolders: [unrelatedRoot], olderThan: gen + 1000)
    guard try await store.track(id: looseID) != nil else {
        printFail(number, "FS-4: loose track was swept by an unrelated root's orphan sweep"); return false
    }

    // Remove the unrelated root entirely — the loose track must still survive.
    try await store.removeRoot(id: unrelatedRoot)
    guard let survivor = try await store.track(id: looseID), survivor.folderID == nil else {
        printFail(number, "FS-4: loose track did not survive removeRoot of an unrelated root"); return false
    }
    return true
}
