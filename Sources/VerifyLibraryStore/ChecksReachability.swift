// ChecksReachability — S8.4 Slice 5b headless checks: the reconcile reachability precheck
// (`RootReachabilityProbe`) and root identity re-stamp (`restampRoot`). The volume-unmount /
// NSWorkspace / remount behaviors are manual (they need a real drive); these pin the pure logic.

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
        guard !RootReachabilityProbe.isReachable(gone) else {
            printFail(number, "reachability: a non-existent path was reported reachable"); return false
        }
        printPass(number, "reachability probe: a live directory is reachable; a file or a missing path is "
            + "NOT — the precheck that skips a reconcile of an unmounted/deleted root (the empty-walk "
            + "backstop remains the actual safety)")
        return true
    } catch {
        printFail(number, "reachability threw: \(error)"); return false
    }
}

// MARK: - Root identity re-stamp (remount)

func checkRestampRoot(number: Int, url: URL) async -> Bool {
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let rootA = try ScanFixtureBuilder.makeCaseRoot("restamp-A")
        let rootB = try ScanFixtureBuilder.makeCaseRoot("restamp-B")
        let rootC = try ScanFixtureBuilder.makeCaseRoot("restamp-C")
        let idA = try await store.addRoot(rootA, dev: 1, inode: 1)
        // Re-stamp A's on-disk identity to (5,5), as a remount with a new device number would.
        try await store.restampRoot(id: idA, dev: 5, inode: 5)
        // A NEW path carrying the re-stamped identity dedups to A → the re-stamp took effect.
        guard try await store.addRoot(rootB, dev: 5, inode: 5) == idA else {
            printFail(number, "restamp: a root with the re-stamped (dev,inode) did NOT dedup to it"); return false
        }
        // A NEW path carrying the OLD identity no longer matches A → a distinct root.
        guard try await store.addRoot(rootC, dev: 1, inode: 1) != idA else {
            printFail(number, "restamp: the OLD (dev,inode) still matched after the re-stamp"); return false
        }
        printPass(number, "restampRoot: refreshes a root's on-disk (dev,inode) identity so a remount with a "
            + "new device number keeps addRoot's identity-dedup (QS3) correct")
        return true
    } catch {
        printFail(number, "restamp threw: \(error)"); return false
    }
}
