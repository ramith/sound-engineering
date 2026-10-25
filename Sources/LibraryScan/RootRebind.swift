// RootRebind — "Use this drive", the filesystem side (R1.1-B, US-R1F-03 LIB-VOL-1; seam S4).
//
// A paused music folder's songs are looked for under the folder the user chose on the new drive, by each
// song's path under its music folder and its size (`LibraryStore.relativePaths`) — not by (dev, inode),
// which another drive never shares (the S8.4 move-match's signature). A song is FOUND when a regular file
// of its size is at that path; a copy of another size is another file (re-tagged since) and counts as
// missing. The store then re-roots the folder in one transaction, keeping what was found and removing
// the rest — or refuses, writing nothing, when none is found (`LibraryStore.rebindRoot`).
//
// Unicode: the library stores paths composed (NFC, `PathNormalizer`) while a drive may hold names
// decomposed (NFD — HFS+, or a copy from one). A Mac volume finds either spelling by the other, so a song
// is first looked for at its stored path; on a drive that does not (some non-Apple file systems), each
// component is matched against the directory's names read through `PathNormalizer`.

import Foundation
import LibraryStore

/// Rebinds a paused music folder to the folder that holds its songs on another drive.
public struct RootRebinder: Sendable {
    /// Reads what is at a folder's path: the drive it is on, and its `(dev, inode)` — the scanner's seam
    /// (`RootReachabilityProbe.identity`), so a test stands in a drive without mounting one.
    let rootIdentity: @Sendable (URL) -> RootIdentity?

    /// Songs read from the store per page.
    private static let pageSize = 256

    public init(rootIdentity: @escaping @Sendable (URL) -> RootIdentity? = RootReachabilityProbe.identity(of:)) {
        self.rootIdentity = rootIdentity
    }

    /// Look for `folderID`'s songs under `newRoot` and re-root the folder there (see the file header). A
    /// `newRoot` that is not a reachable folder finds none of them: refused, nothing written.
    public func rebind(folderID: Int64, to newRoot: URL, in store: LibraryStore) async throws -> RebindOutcome {
        guard let identity = rootIdentity(newRoot) else { return .refused(.noSongsFound) }
        var lookedAt = Set<Int64>()
        var found = Set<Int64>()
        var resolver = DriveLookup(root: newRoot)
        var afterID: Int64 = 0
        while true {
            let page = try await store.relativePaths(inFolder: folderID, afterID: afterID, limit: Self.pageSize)
            guard let last = page.last else { break }
            for song in page {
                try Task.checkCancellation()
                lookedAt.insert(song.id)
                if resolver.holdsFile(at: song.relativePath, ofSize: song.fileSize) {
                    found.insert(song.id)
                }
            }
            afterID = last.id
        }
        return try await store.rebindRoot(folderID, to: newRoot, identity: identity, found: found,
                                          lookedAt: lookedAt)
    }
}

/// Finds files under one folder of a drive by their stored (NFC) relative paths — at that path when the
/// drive finds it, else component by component through each directory's names, read through
/// `PathNormalizer` and kept for the songs that follow.
struct DriveLookup {
    let root: URL
    /// Each directory's entries already read, by directory path: NFC name → the name on the drive.
    private var listings: [String: [String: String]] = [:]

    init(root: URL) {
        self.root = root
    }

    /// Whether a regular file of `size` bytes is at `relativePath` under the root.
    mutating func holdsFile(at relativePath: String, ofSize size: Int64) -> Bool {
        guard let url = locate(relativePath), let attributes = FileSignature.attributes(of: url) else { return false }
        return attributes.isRegularFile && attributes.fileSize == size
    }

    /// The file at `relativePath` under the root, as the drive spells it — nil when there is none.
    private mutating func locate(_ relativePath: String) -> URL? {
        let direct = root.appendingPathComponent(relativePath)
        if !FileSignature.isAbsent(direct) {
            return direct
        }
        var directory = root
        for component in relativePath.split(separator: "/").map({ PathNormalizer.normalizedComponent(String($0)) }) {
            let child = directory.appendingPathComponent(component)
            if !FileSignature.isAbsent(child) {
                directory = child
            } else if let spelled = entries(of: directory)[PathNormalizer.normalizedComponent(component)] {
                directory = directory.appendingPathComponent(spelled)
            } else {
                return nil
            }
        }
        return directory
    }

    /// `directory`'s entry names keyed by their NFC spelling (read once per directory).
    private mutating func entries(of directory: URL) -> [String: String] {
        if let known = listings[directory.path] {
            return known
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var byNormalized: [String: String] = [:]
        for name in names {
            byNormalized[PathNormalizer.normalizedComponent(name)] = name
        }
        listings[directory.path] = byNormalized
        return byNormalized
    }
}
