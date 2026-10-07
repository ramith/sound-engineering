// StoreBackup — a consistent copy of the store, taken before its schema is upgraded.
//
// A migration rewrites the one file that holds the user's playlists and play history (v7, for one,
// rebuilds the `albums` table). So before the open path upgrades an EXISTING store, it copies it
// beside itself with SQLite's online backup (GRDB `backup(to:)`): a page-for-page snapshot,
// consistent even against a live WAL. A backup that fails stops the upgrade — the open path refuses
// rather than migrate without one (`StoreOpenRefusal.backupFailed`). Only the newest `keepCount`
// backups are kept, and what a crash mid-backup left (a `.partial` copy + its journal) is cleared
// at the next backup.
//
// Named `library.pre-v<N>-<stamp>.sqlite3`, N being the schema version upgraded TO. The stamp is
// passed in, as for StoreQuarantine, so the harness can assert exact names and their order.

import Foundation
import GRDB

/// Writes and prunes the pre-upgrade backups that sit beside the store.
public enum StoreBackup {
    /// How many backups are kept; older ones are pruned after each new one is written.
    public static let keepCount = 2

    /// The backup name for a store, target version and stamp:
    /// `library.sqlite3`, 7, "20261008-120000" → `library.pre-v7-20261008-120000.sqlite3`.
    public static func backupURL(for storeURL: URL, targetVersion: Int, stamp: String) -> URL {
        let name = "\(namePrefix(of: storeURL))\(targetVersion)-\(stamp)\(nameSuffix(of: storeURL))"
        return storeURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// The backups beside `storeURL`, oldest first. Ordered by stamp (`defaultStamp` sorts by
    /// time), never by name — a name sort would put a `pre-v10` backup before a `pre-v9` one.
    public static func backups(of storeURL: URL) throws -> [URL] {
        let directory = storeURL.deletingLastPathComponent()
        let prefix = namePrefix(of: storeURL)
        let suffix = nameSuffix(of: storeURL)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let stamped = names.compactMap { name -> (stamp: Substring, url: URL)? in
            // `<version>-<stamp>` sits between the prefix and the suffix; the stamp follows the first dash.
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
            let versionAndStamp = name.dropFirst(prefix.count).dropLast(suffix.count)
            guard let dash = versionAndStamp.firstIndex(of: "-") else { return nil }
            return (versionAndStamp[versionAndStamp.index(after: dash)...], directory.appendingPathComponent(name))
        }
        return stamped.sorted { $0.stamp < $1.stamp }.map(\.url)
    }

    /// Copy `source` (the store at `storeURL`) to its backup, then prune the oldest. The copy is
    /// written under a temporary name and renamed into place, so a file under a backup name is
    /// always a complete copy; a temporary one a crash left behind is removed first.
    static func backUp(_ source: any DatabaseReader, storeURL: URL, targetVersion: Int, stamp: String) throws {
        removeStalePartials(storeURL)
        let destination = backupURL(for: storeURL, targetVersion: targetVersion, stamp: stamp)
        let partial = destination.appendingPathExtension("partial")
        do {
            let copy = try DatabaseQueue(path: partial.path)
            try source.backup(to: copy)
            try copy.close()
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        prune(storeURL)
    }

    /// Delete all but the newest `keepCount` backups (with any sidecars). Best effort: an old backup
    /// that can't be deleted costs disk space, never the open.
    private static func prune(_ storeURL: URL) {
        guard let all = try? backups(of: storeURL) else { return }
        for old in all.dropLast(keepCount) {
            for file in [old.path] + StoreQuarantine.sidecarSuffixes.map({ old.path + $0 }) {
                try? FileManager.default.removeItem(atPath: file)
            }
        }
    }

    /// Delete every unfinished backup beside `storeURL` — `<backup name>.partial` and its journal or
    /// sidecars (`.partial-journal`, `-wal`, `-shm`). Only a crash mid-copy leaves one: a finished copy
    /// is renamed. Best effort, like `prune`.
    private static func removeStalePartials(_ storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()
        let prefix = namePrefix(of: storeURL)
        let marker = nameSuffix(of: storeURL) + ".partial"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) && name.contains(marker) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// `library.sqlite3` → `library.pre-v`.
    private static func namePrefix(of storeURL: URL) -> String {
        "\(storeURL.deletingPathExtension().lastPathComponent).pre-v"
    }

    /// `library.sqlite3` → `.sqlite3` (empty for an extensionless store).
    private static func nameSuffix(of storeURL: URL) -> String {
        storeURL.pathExtension.isEmpty ? "" : ".\(storeURL.pathExtension)"
    }
}
