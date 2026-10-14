// ChecksReachability — S8.4 Slice 5b headless checks: the reachability probe
// (`RootReachabilityProbe`) and the root identity re-stamp (`restampRoot`), which since R1 binds a
// root to its drive and refuses another one. The volume-unmount / NSWorkspace / remount behaviors are
// manual (they need a real drive); these pin the pure logic (ChecksSweepEvidence walks it).

import Foundation
import LibraryScan
import LibraryStore

// MARK: - Reachability precheck

func checkRootReachability(number: Int, url _: URL) async -> Bool {
    do {
        let dir = try ScanFixtureBuilder.makeCaseRoot("reachable")
        guard RootReachabilityProbe.isReachable(dir) else {
            printFail(number, "reachability: a real directory was reported unreachable"); return false
        }
        let file = try ScanFixtureBuilder.writeFile(at: dir, fileName: "x.flac")
        guard !RootReachabilityProbe.isReachable(file) else {
            printFail(number, "reachability: a FILE was reported reachable (must be a directory)"); return false
        }
        let gone = dir.appendingPathComponent("nope-\(UUID().uuidString)", isDirectory: true)
        guard !RootReachabilityProbe.isReachable(gone), RootReachabilityProbe.identity(of: gone) == nil else {
            printFail(number, "reachability: a non-existent path was reported reachable"); return false
        }
        // The fixture is on the startup volume: its identity is its lstat, unbound to any drive.
        let signature = LibraryScanner.deviceInode(of: dir)
        guard RootReachabilityProbe.identity(of: dir)
            == RootIdentity(dev: signature.dev, inode: signature.inode, volumeUUID: nil) else {
            printFail(number, "reachability: a folder on the startup volume read a volume UUID, or not its lstat")
            return false
        }
        printPass(number, "reachability probe: a live directory is reachable; a file or a missing path is "
            + "NOT — what a walk reads first, so an unmounted/deleted root is not walked (SweepRefusal); a "
            + "folder on the startup volume reads its lstat and no volume UUID (unbound by design)")
        return true
    } catch {
        printFail(number, "reachability threw: \(error)"); return false
    }
}

// MARK: - Root identity re-stamp (remount; another drive at the path)

func checkRestampRoot(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        guard try await restampFollowsTheRootsOwnDrive(store, number: number),
              try await restampOfAnUnboundRoot(store, number: number) else { return false }
        printPass(number, "restampRoot: binds an unbound root to its drive, then refreshes its on-disk "
            + "(dev,inode) on THAT drive (a remount's new device number keeps addRoot's dedup, QS3, "
            + "correct) and refuses — changing nothing — another drive at its path, or one with no UUID; "
            + "a root on a volume with no UUID stays unbound (known limitation); a missing root is a no-op")
        return true
    } catch {
        printFail(number, "restamp threw: \(error)"); return false
    }
}

/// A root bound to drive A: re-stamped on A (a remount with a new st_dev) it follows; drive B, or a
/// volume with no UUID, at its path is refused and leaves the stamp as it was.
private func restampFollowsTheRootsOwnDrive(_ store: LibraryStore, number: Int) async throws -> Bool {
    let idA = try await store.addRoot(ScanFixtureBuilder.makeCaseRoot("restamp-A"), dev: 1, inode: 1)
    guard try await store.restampRoot(id: idA, to: RootIdentity(dev: 5, inode: 5, volumeUUID: "VOL-A")),
          try await store.addRoot(ScanFixtureBuilder.makeCaseRoot("restamp-B"), dev: 5, inode: 5) == idA,
          try await store.addRoot(ScanFixtureBuilder.makeCaseRoot("restamp-C"), dev: 1, inode: 1) != idA else {
        printFail(number, "restamp: binding an unbound root did not refresh its (dev,inode)"); return false
    }
    let otherDrives = [
        RootIdentity(dev: 9, inode: 9, volumeUUID: "VOL-B"), RootIdentity(dev: 9, inode: 9, volumeUUID: nil),
    ]
    for other in otherDrives {
        guard try await !store.restampRoot(id: idA, to: other) else {
            printFail(number, "restamp: another drive (\(other.volumeUUID ?? "no UUID")) was accepted"); return false
        }
    }
    guard try await store.addRoot(ScanFixtureBuilder.makeCaseRoot("restamp-D"), dev: 9, inode: 9) != idA,
          try await store.restampRoot(id: idA, to: RootIdentity(dev: 6, inode: 6, volumeUUID: "VOL-A")),
          try await store.addRoot(ScanFixtureBuilder.makeCaseRoot("restamp-E"), dev: 6, inode: 6) == idA else {
        printFail(number, "restamp: a refused drive re-stamped the root, or its own drive's remount did not")
        return false
    }
    guard try await store.restampRoot(id: 999_999, to: RootIdentity(dev: 1, inode: 1, volumeUUID: "VOL-A")) else {
        printFail(number, "restamp: a missing folder id was refused (expected a no-op)"); return false
    }
    return true
}

/// A root on a volume with no UUID stays unbound (today's behaviour, the documented limitation): any
/// volume re-stamps it, and the first with a UUID binds it.
private func restampOfAnUnboundRoot(_ store: LibraryStore, number: Int) async throws -> Bool {
    let idF = try await store.addRoot(ScanFixtureBuilder.makeCaseRoot("restamp-F"), dev: 20, inode: 20)
    guard try await store.restampRoot(id: idF, to: RootIdentity(dev: 21, inode: 21, volumeUUID: nil)),
          try await store.restampRoot(id: idF, to: RootIdentity(dev: 22, inode: 22, volumeUUID: "VOL-C")),
          try await !store.restampRoot(id: idF, to: RootIdentity(dev: 23, inode: 23, volumeUUID: "VOL-D")) else {
        printFail(number, "restamp: a root with no volume UUID did not stay unbound until one with a UUID")
        return false
    }
    return true
}
