import Foundation
import LibraryScan
import LibraryStore
import Testing

// MARK: - R1.1-B break-it, "Use this drive": the store and the scanner's halves (BI-P)

//
// Red tests written against the combined sprint branch (34ad6efe): the shipped `RootRebinder` and
// `LibraryStore.rebindRoot` over a real store and real folders, the drive's identity read through the
// scanner's seam (`rootIdentity`) so a test stands in a drive without mounting one.

@Suite("R1.1-B break-it — “Use this drive”, store and scanner (BI-P)")
struct BreakItRebindTests {
    @Test("BI-P06: a gone drive's stale device number must not refuse the rebind as “already in your library”")
    func staleIdentityOfAGoneDriveDoesNotRefuse() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("bi-rebind-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try await LibraryStore(url: base.appendingPathComponent("library.sqlite3"), appBuild: "test")
        // Two music folders, each a whole drive — a volume's top folder is inode 2 on APFS and HFS+ — and
        // both drives unplugged: their stored (dev, inode) are what their last mount had.
        let music = URL(fileURLWithPath: "/Volumes/BI-Music", isDirectory: true)
        let backup = URL(fileURLWithPath: "/Volumes/BI-Backup", isDirectory: true)
        let musicID = try await store.addRoot(music, dev: 16_777_240, inode: 2)
        let backupID = try await store.addRoot(backup, dev: 16_777_241, inode: 2)
        try #require(musicID != backupID)
        _ = try await store.restampRoot(id: musicID, to: RootIdentity(dev: 16_777_240, inode: 2, volume: "VOL-MUSIC"))
        _ = try await store.restampRoot(id: backupID, to: RootIdentity(dev: 16_777_241, inode: 2, volume: "VOL-BACKUP"))
        let song = ScannedFile(url: music.appendingPathComponent("Album/01 Song.flac"), relativePath: "Album/",
                               name: "01 Song", format: "FLAC", fileSize: 10, mtime: 1)
        _ = try await store.upsert([song], folderID: musicID, generation: store.beginScanGeneration())

        // The Music drive's copy, plugged in under a new name. macOS hands device numbers out again after an
        // unmount: this mount got the one the Backup drive had. Its top folder is inode 2, as every drive's.
        let newRoot = base.appendingPathComponent("BI-Music 1", isDirectory: true)
        try FileManager.default.createDirectory(at: newRoot.appendingPathComponent("Album", isDirectory: true),
                                                withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: newRoot.appendingPathComponent("Album/01 Song.flac").path,
                                       contents: Data(count: 10))
        let key = PathNormalizer.normalizedString(for: newRoot)
        let rebinder = RootRebinder { url in
            PathNormalizer.normalizedString(for: url) == key
                ? RootIdentity(dev: 16_777_241, inode: 2, volume: "VOL-NEW") : nil
        }
        let outcome = try await rebinder.rebind(folderID: musicID, to: newRoot, in: store)
        #expect(outcome == .rebound(kept: 1, removed: 0),
                Comment(rawValue: "refused as overlapping the Backup folder: rebindRoot's “same directory” test "
                    + "compares the new drive's (dev, inode) with a GONE drive's stored ones, without the volume "
                    + "— got \(outcome)"))
    }
}
