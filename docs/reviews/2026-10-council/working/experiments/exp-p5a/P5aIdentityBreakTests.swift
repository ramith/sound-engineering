import Foundation
import LibraryScan
import LibraryStore
import Testing

// P5a panel — UNCOMMITTED adversarial tests for identity: move-match across roots (LIB-03), the
// scan generation, hard links, mtime granularity, nested-root validation, path keys.

@Suite("P5a LIB-03 — identity across roots, generations, links, paths", .serialized)
struct P5aIdentityBreakTests {
    private struct TwoRoots {
        let base: URL
        let rootA: URL
        let rootB: URL
        let store: LibraryStore
        let idA: Int64
        let idB: Int64
        let song: URL
        let songID: Int64
        let playlist: Int64
    }

    /// Two sibling roots A and B on one volume; A holds the user's song (in a playlist, played 3x).
    private func makeTwoRoots(_ tag: String) async throws -> TwoRoots {
        let base = P5aFixture.base(tag)
        let rootA = base.appendingPathComponent("Music A", isDirectory: true)
        let rootB = base.appendingPathComponent("Music B", isDirectory: true)
        let aFiles = try P5aFixture.files(in: rootA.appendingPathComponent("Album"), count: 30, prefix: "A")
        try P5aFixture.files(in: rootB.appendingPathComponent("Album"), count: 30, prefix: "B")
        let store = try await P5aFixture.store(base)
        let idA = try await store.addRoot(rootA)
        let idB = try await store.addRoot(rootB)
        _ = try await LibraryScanner().scan(root: rootA, folderID: idA, into: store)
        _ = try await LibraryScanner().scan(root: rootB, folderID: idB, into: store)
        let song = aFiles[7]
        let songID = try #require(try await store.track(url: song)).id
        let playlist = try await store.createPlaylist(name: "Favourites")
        _ = try await store.appendEntry(playlistID: playlist, trackID: songID)
        for when in 0 ..< 3 {
            try await store.incrementPlayCount(id: songID, playedAt: 1_760_000_000 + Int64(when))
        }
        return TwoRoots(base: base, rootA: rootA, rootB: rootB, store: store, idA: idA, idB: idB,
                        song: song, songID: songID, playlist: playlist)
    }

    /// Move the song from root A to root B (a rename on one volume: same dev, inode, size, mtime).
    private func moveSong(_ setup: TwoRoots) throws -> URL {
        let target = setup.rootB.appendingPathComponent("Album").appendingPathComponent(setup.song.lastPathComponent)
        try FileManager.default.moveItem(at: setup.song, to: target)
        return target
    }

    @Test("LIB-03a: a cross-root move keeps its id when the OLD root reconciles first", arguments: [true, false])
    func crossRootMoveOrder(oldRootFirst: Bool) async throws {
        let setup = try await makeTwoRoots("lib03a")
        defer { try? FileManager.default.removeItem(at: setup.base) }
        let target = try moveSong(setup)
        let order = oldRootFirst ? [(setup.rootA, setup.idA), (setup.rootB, setup.idB)]
            : [(setup.rootB, setup.idB), (setup.rootA, setup.idA)]
        for (root, id) in order {
            _ = try await LibraryScanner().scan(root: root, folderID: id, into: setup.store)
        }
        let moved = try await setup.store.track(url: target)
        let after = try await P5aFixture.userData(setup.store, trackID: setup.songID, playlistID: setup.playlist)
        print("P5A LIB-03a oldRootFirst=\(oldRootFirst) newID=\(String(describing: moved?.id)) oldID=\(setup.songID) "
            + "entries=\(after.entries) plays=\(String(describing: after.playCount))")
        #expect(moved?.id == setup.songID, "the moved song got a new id; its playlist entry + plays were deleted")
        #expect(after.entries == 1 && after.playCount == 3)
    }

    /// The app's real shape: one FSEvents batch touches both roots, both 1 s debounces fire, and
    /// FolderWalkSchedule starts both reconciles at once (different folders).
    @Test("LIB-03b: concurrent reconciles of both roots after a cross-root move (20 trials)")
    func crossRootMoveConcurrent() async throws {
        var lost = 0
        var sameGeneration = 0
        let trials = 20
        for _ in 0 ..< trials {
            let setup = try await makeTwoRoots("lib03b")
            defer { try? FileManager.default.removeItem(at: setup.base) }
            let target = try moveSong(setup)
            let store = setup.store
            async let walkA = LibraryScanner().scan(root: setup.rootA, folderID: setup.idA, into: store)
            async let walkB = LibraryScanner().scan(root: setup.rootB, folderID: setup.idB, into: store)
            let (resultA, resultB) = try await (walkA, walkB)
            if resultA.generation == resultB.generation {
                sameGeneration += 1
            }
            if try await store.track(url: target)?.id != setup.songID {
                lost += 1
            }
        }
        print("P5A LIB-03b trials=\(trials) idLost=\(lost) sameGeneration=\(sameGeneration)")
        #expect(lost == 0, "\(lost)/\(trials) concurrent cross-root moves lost the song's id and user data")
        #expect(sameGeneration == 0, "\(sameGeneration)/\(trials) concurrent walks shared one generation")
    }

    /// The generation is max(last_seen)+1 read OUTSIDE the stamping write, so two walks share it.
    /// A row the old root's walk stamped at G is then not a move candidate for the new root's walk
    /// at the same G (`last_seen_scan < G`): a NEW id, and a ghost row the old sweep keeps.
    @Test("LIB-03c: a shared generation turns a move into a new id plus a ghost row")
    func sharedGenerationMove() async throws {
        let setup = try await makeTwoRoots("lib03c")
        defer { try? FileManager.default.removeItem(at: setup.base) }
        let store = setup.store
        let generationA = try await store.beginScanGeneration()
        let generationB = try await store.beginScanGeneration()
        #expect(generationA == generationB) // nothing reserves a generation
        // Walk A enumerates the song at its OLD url (before the move), stamping it at G.
        let old = try #require(LibraryScanner.makeScannedFile(fileURL: setup.song, root: setup.rootA))
        _ = try await store.upsertReconciling([old], folderID: setup.idA, generation: generationA)
        // The user moves it; walk B (same G) sees the new url.
        let target = try moveSong(setup)
        let new = try #require(LibraryScanner.makeScannedFile(fileURL: target, root: setup.rootB))
        let ids = try await store.upsertReconciling([new], folderID: setup.idB, generation: generationB)
        let sweptA = try await store.sweepOrphans(inFolders: [setup.idA], olderThan: generationA)
        let ghost = try await store.track(id: setup.songID)
        print("P5A LIB-03c G=\(generationA) newID=\(ids[0]) oldID=\(setup.songID) ghostStillThere=\(ghost != nil) "
            + "ghostURL=\(ghost?.url.lastPathComponent ?? "-") sweptA=\(sweptA)")
        #expect(ids[0] == setup.songID, "the move minted a new id")
    }

    /// Hard links: two urls, one inode. Renaming one link must keep that link's id.
    @Test("LIB-03d: renaming one of two hard links keeps its id")
    func hardLinkRename() async throws {
        let base = P5aFixture.base("lib03d")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music.appendingPathComponent("Other"), count: 3)
        let first = music.appendingPathComponent("Linked/one.flac")
        let second = music.appendingPathComponent("Linked/two.flac")
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: first.path, contents: Data([9, 9, 9]))
        #expect(link(first.path, second.path) == 0)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let firstID = try #require(try await store.track(url: first)).id
        var results: [String] = []
        for name in ["aaa.flac", "zzz.flac", "mmm.flac", "000.flac", "one.flac"] {
            let current = try #require(try await store.track(id: firstID)?.url)
            let renamed = first.deletingLastPathComponent().appendingPathComponent(name)
            if current.lastPathComponent == name { continue }
            try FileManager.default.moveItem(at: current, to: renamed)
            _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
            let id = try await store.track(url: renamed)?.id
            results.append("\(name):\(id == firstID ? "kept" : "LOST")")
            if id != firstID { break }
        }
        print("P5A LIB-03d hard-link renames: \(results.joined(separator: " "))")
        #expect(!results.contains { $0.hasSuffix("LOST") })
    }

    /// An in-place rewrite of the same size inside the same wall-clock second (a tag editor writing
    /// into ID3 padding twice, a re-encode with a fixed size) — whole-second mtime cannot see it.
    @Test("LIB-03e: a same-size rewrite within the same second is re-read")
    func sameSecondRewrite() async throws {
        let base = P5aFixture.base("lib03e")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: 2)
        let stamp = Date(timeIntervalSince1970: 1_760_000_000.100)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: files[0].path)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        let first = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let id = try #require(try await store.track(url: files[0])).id
        try await store.markMetadataScanned(trackID: id, generation: first.generation)
        // Rewrite: new bytes, same size, mtime moves by 0.8 s inside the same second.
        try Data([0xAA, 0xBB, 0xCC]).write(to: files[0])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_760_000_000.900)],
                                              ofItemAtPath: files[0].path)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let pending = try await store.tracksNeedingMetadata(limit: 10, inFolder: root)
        print("P5A LIB-03e pendingAfterRewrite=\(pending.contains(id))")
        #expect(pending.contains(id), "a changed file was classified unchanged (whole-second mtime)")
    }

    /// A nested root spelled in a different case on a case-insensitive volume, and a root that is a
    /// symlink into another root.
    @Test("LIB-03f: a nested root in another case / via a symlink is rejected")
    func nestedRootSpellings() async throws {
        let base = P5aFixture.base("lib03f")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music.appendingPathComponent("Rock"), count: 4)
        let lower = base.appendingPathComponent("music/rock", isDirectory: true)
        let link = base.appendingPathComponent("RockLink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: music.appendingPathComponent("Rock"))
        var rejectedCase = false
        do {
            try LibraryScanner().validateNewRoot(lower, against: [music])
        } catch is NestedRootConflict {
            rejectedCase = true
        }
        var rejectedLink = false
        do {
            try LibraryScanner().validateNewRoot(link, against: [music])
        } catch is NestedRootConflict {
            rejectedLink = true
        }
        // Consequence if accepted: register both and walk both.
        let store = try await P5aFixture.store(base)
        let outer = try await store.addRoot(music, dev: LibraryScanner.deviceInode(of: music).dev,
                                            inode: LibraryScanner.deviceInode(of: music).inode)
        let signature = LibraryScanner.deviceInode(of: lower)
        let inner = try await store.addRoot(lower, dev: signature.dev, inode: signature.inode)
        _ = try await LibraryScanner().scan(root: music, folderID: outer, into: store)
        _ = try await LibraryScanner().scan(root: lower, folderID: inner, into: store)
        let rows = try await store.trackCount()
        print("P5A LIB-03f caseVariantRejected=\(rejectedCase) symlinkRejected=\(rejectedLink) "
            + "innerRootID=\(inner) outerRootID=\(outer) rowsFor\(files.count)Files=\(rows)")
        #expect(rejectedCase, "a case-variant nested root was accepted")
        #expect(rows == files.count, "one file on disk became \(rows / files.count) rows")
    }

    /// NFD filename (as HFS+ and many zip/rsync copies leave them): one row, NFC key, still opens.
    @Test("LIB-03g: an NFD filename gets an NFC key that still opens")
    func nfdFilename() async throws {
        let base = P5aFixture.base("lib03g")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let nfd = "Cafe\u{301} \u{1100}\u{1161}.flac" // "Café 가" decomposed
        FileManager.default.createFile(atPath: music.appendingPathComponent(nfd).path, contents: Data([1]))
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let rows = try await store.tracks(inFolder: root)
        let key = rows.first?.url.path ?? ""
        let isNFC = key == key.precomposedStringWithCanonicalMapping
        let opens = FileManager.default.fileExists(atPath: key)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let rowsAfterRescan = try await store.trackCount(inFolder: root)
        print("P5A LIB-03g rows=\(rows.count) keyIsNFC=\(isNFC) keyOpens=\(opens) "
            + "storedName=\(rows.first.map { $0.name.unicodeScalars.count } ?? 0)scalars rowsAfterRescan=\(rowsAfterRescan)")
        #expect(rows.count == 1 && isNFC && opens && rowsAfterRescan == 1)
    }

    /// PathNormalizer claims to be pure ("no filesystem access"): the same spelling must give the
    /// same key whether or not the file exists.
    @Test("LIB-03h: PathNormalizer gives one key regardless of file existence")
    func normalizerPurity() throws {
        let existing = PathNormalizer.normalizedString(forPath: "/private/tmp")
        let missing = PathNormalizer.normalizedString(forPath: "/private/tmp/p5a-does-not-exist")
        print("P5A LIB-03h /private/tmp -> \(existing); /private/tmp/<missing> -> \(missing)")
        #expect(missing.hasPrefix(existing + "/"), "the key prefix depends on whether the file exists")
    }
}

@Suite("P5a LIB-03 — concurrent reconcile, small old root vs large new root", .serialized)
struct P5aCrossRootRaceTests {
    @Test("LIB-03b2: concurrent reconciles, old root small, new root large (10 trials)")
    func asymmetricRace() async throws {
        var lost = 0
        let trials = 10
        for _ in 0 ..< trials {
            let base = P5aFixture.base("lib03b2")
            defer { try? FileManager.default.removeItem(at: base) }
            let rootA = base.appendingPathComponent("Small", isDirectory: true)
            let rootB = base.appendingPathComponent("Large", isDirectory: true)
            let aFiles = try P5aFixture.files(in: rootA, count: 3, prefix: "A")
            for album in 0 ..< 12 {
                try P5aFixture.files(in: rootB.appendingPathComponent("Album \(album)"), count: 250, prefix: "B")
            }
            let store = try await P5aFixture.store(base)
            let idA = try await store.addRoot(rootA)
            let idB = try await store.addRoot(rootB)
            _ = try await LibraryScanner().scan(root: rootA, folderID: idA, into: store)
            _ = try await LibraryScanner().scan(root: rootB, folderID: idB, into: store)
            let songID = try #require(try await store.track(url: aFiles[1])).id
            let target = rootB.appendingPathComponent("Album 11").appendingPathComponent("zz moved.flac")
            try FileManager.default.moveItem(at: aFiles[1], to: target)
            async let walkA = LibraryScanner().scan(root: rootA, folderID: idA, into: store)
            async let walkB = LibraryScanner().scan(root: rootB, folderID: idB, into: store)
            _ = try await (walkA, walkB)
            if try await store.track(url: target)?.id != songID {
                lost += 1
            }
        }
        print("P5A LIB-03b2 trials=\(trials) idLost=\(lost)")
        #expect(lost == 0, "\(lost)/\(trials) concurrent cross-root moves lost the song's id and user data")
    }

    /// The accepted case-variant nested root: does each walk steal the other's rows?
    @Test("LIB-03f2: a case-variant nested root ping-pongs rows between the two roots")
    func caseVariantPingPong() async throws {
        let base = P5aFixture.base("lib03f2")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        try P5aFixture.files(in: music.appendingPathComponent("Rock"), count: 4)
        let lower = base.appendingPathComponent("music/rock", isDirectory: true)
        let store = try await P5aFixture.store(base)
        let outer = try await store.addRoot(music)
        let inner = try await store.addRoot(lower)
        var trace: [String] = []
        for (root, id) in [(music, outer), (lower, inner), (music, outer), (lower, inner)] {
            let result = try await LibraryScanner().scan(root: root, folderID: id, into: store)
            let inOuter = try await store.trackCount(inFolder: outer)
            let inInner = try await store.trackCount(inFolder: inner)
            trace.append("walk(\(id)) gen=\(result.generation) swept=\(result.orphansSwept) outer=\(inOuter) inner=\(inInner)")
        }
        // Concurrent: same generation → no move candidates → duplicates?
        async let walkOuter = LibraryScanner().scan(root: music, folderID: outer, into: store)
        async let walkInner = LibraryScanner().scan(root: lower, folderID: inner, into: store)
        _ = try await (walkOuter, walkInner)
        let total = try await store.trackCount()
        print("P5A LIB-03f2 \(trace.joined(separator: " | ")) | concurrent: totalRows=\(total) for 4 files")
        #expect(total == 4)
    }
}

@Suite("P5a metadata pass — a file changed between extract and apply")
struct P5aMetadataRaceTests {
    /// The pass extracts a song's tags off the store, then applies them. If a reconcile re-stamps the
    /// song as modified (metadata_scanned = 0) in between — the user retagged it while the pass ran —
    /// the late apply writes the OLD tags and marks it scanned, so the new tags are never read.
    @Test("META-1: an apply of tags read before a modification leaves the song pending")
    func staleApplyAfterModification() async throws {
        let base = P5aFixture.base("meta1")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: 2)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        let scan = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let id = try #require(try await store.track(url: files[0])).id
        // 1. The pass snapshots pending and extracts the OLD tags (off the store).
        let pending = try await store.tracksNeedingMetadata(limit: 10, inFolder: root)
        #expect(pending.contains(id))
        let oldTags = TrackMetadata(title: "Old Title")
        // 2. Meanwhile the user retags the file; a reconcile sees size/mtime change.
        try Data([7, 7, 7, 7, 7, 7]).write(to: files[0])
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let pendingAfterEdit = try await store.tracksNeedingMetadata(limit: 10, inFolder: root).contains(id)
        // 3. The pass applies what it read in step 1.
        try await store.applyExtractedResult(trackID: id, meta: oldTags, artwork: nil, generation: scan.generation)
        let pendingAfterApply = try await store.tracksNeedingMetadata(limit: 10, inFolder: root).contains(id)
        print("P5A META-1 pendingAfterEdit=\(pendingAfterEdit) pendingAfterStaleApply=\(pendingAfterApply)")
        #expect(pendingAfterApply, "the stale apply marked a modified song scanned; its new tags are never read")
    }
}

@Suite("P5a upsert — a file replaced in place keeps its move-signature current")
struct P5aReplaceInPlaceTests {
    /// Time Machine / backup restore, `cp -p` + `mv`, an rsync temp-and-rename: same path, same
    /// bytes, same size and mtime — a NEW inode. The upsert's no-op WHERE ignores dev/inode, so the
    /// row keeps the dead inode; the next rename of the file cannot be move-matched.
    @Test("UPS-1: after a replace-in-place, a rename still keeps the song's id")
    func replaceInPlaceThenRename() async throws {
        let base = P5aFixture.base("ups1")
        defer { try? FileManager.default.removeItem(at: base) }
        let music = base.appendingPathComponent("Music", isDirectory: true)
        let files = try P5aFixture.files(in: music, count: 3)
        let store = try await P5aFixture.store(base)
        let root = try await store.addRoot(music)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let song = files[1]
        let id = try #require(try await store.track(url: song)).id
        // Restore-style replace: copy (new inode), keep mtime, rename over the original.
        let temp = base.appendingPathComponent("restore.tmp")
        try FileManager.default.copyItem(at: song, to: temp)
        let mtime = try FileManager.default.attributesOfItem(atPath: song.path)[.modificationDate] as? Date
        try FileManager.default.setAttributes([.modificationDate: mtime as Any], ofItemAtPath: temp.path)
        #expect(rename(temp.path, song.path) == 0)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let storedInode = try await store.track(id: id)?.inode
        let diskInode = LibraryScanner.deviceInode(of: song).inode
        // Now the user renames it.
        let renamed = music.appendingPathComponent("renamed.flac")
        try FileManager.default.moveItem(at: song, to: renamed)
        _ = try await LibraryScanner().scan(root: music, folderID: root, into: store)
        let after = try await store.track(url: renamed)?.id
        print("P5A UPS-1 storedInode=\(String(describing: storedInode)) diskInode=\(String(describing: diskInode)) "
            + "idAfterRename=\(String(describing: after)) originalID=\(id)")
        #expect(storedInode == diskInode, "the row kept a dead inode")
        #expect(after == id, "the rename minted a new id")
    }
}
