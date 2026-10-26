// RootRebind — "Use this drive", the filesystem side (R1.1-B, US-R1F-03 LIB-VOL-1; seam S4).
//
// A paused music folder's songs are looked for under the folder the user chose on the new drive, by each
// song's path under its music folder and its size (`LibraryStore.relativePaths`) — not by (dev, inode),
// which another drive never shares (the S8.4 move-match's signature). A song is FOUND when the walk that
// follows the rebind would read a file of its size at that path: a supported audio file, under folders a
// walk goes into (not hidden, not a package, not a link, not another drive mounted inside). A copy of
// another size is another file (re-tagged since) and counts as missing. The store then re-roots the folder
// in one transaction, keeping what was found and removing the rest — or refuses, writing nothing, when none
// is found (`LibraryStore.rebindRoot`).
//
// What is found is handed over as the walk would read it (`LibraryScanner.admit`): its url as the DRIVE
// spells it and its own (dev, inode). The library stores paths composed (NFC, `PathNormalizer`) while a
// drive may hold names decomposed (NFD — HFS+, or a copy from one), or in another letter case (a Mac volume
// finds "02.flac" when the drive holds "02.FLAC"). Each component is matched against its directory's names:
// the same name first, else the one name that differs only in its normal form or letter case. The rebind
// writes the drive's spelling and the file's (dev, inode), so the walk after it sees each kept song at its
// own url (never a new song at another — break-it BI-P04) and a later rename on the new drive is followed by
// the move-match, as anywhere else (BI-P07).

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
    /// `newRoot` that is not a folder the app can read is refused as such (`.unreadableFolder`), nothing
    /// written.
    public func rebind(folderID: Int64, to newRoot: URL, in store: LibraryStore) async throws -> RebindOutcome {
        var resolver = DriveLookup(root: newRoot)
        guard let identity = rootIdentity(newRoot), resolver.canReadRoot else { return .refused(.unreadableFolder) }
        var lookedAt = Set<Int64>()
        var found: [Int64: ScannedFile] = [:]
        var afterID: Int64 = 0
        while true {
            let page = try await store.relativePaths(inFolder: folderID, afterID: afterID, limit: Self.pageSize)
            guard let last = page.last else { break }
            for song in page {
                try Task.checkCancellation()
                lookedAt.insert(song.id)
                found[song.id] = resolver.file(at: song.relativePath, ofSize: song.fileSize)
            }
            afterID = last.id
        }
        return try await store.rebindRoot(folderID, to: newRoot, identity: identity, found: found,
                                          lookedAt: lookedAt)
    }

    /// Where a music folder at `folderPath` is now, when another folder of the same drive moved from
    /// `oldPath` to `newPath` — the drive's own folders, wherever it is mounted now (plan check §6, "Use
    /// this drive" (10): two paused folders on the same old drive, one choice). The part the two paths END
    /// with in common is the folder's place on the drive ("…/Rock"); what comes before it is where the drive
    /// was and is ("/Volumes/Music" → "/Volumes/Music 1"). nil when `folderPath` is not under where the drive
    /// was. All paths in the stored form (`PathNormalizer`).
    public static func location(of folderPath: String, movedFrom oldPath: String, to newPath: String) -> String? {
        var old = oldPath.split(separator: "/", omittingEmptySubsequences: true)
        var new = newPath.split(separator: "/", omittingEmptySubsequences: true)
        while let lastOld = old.last, let lastNew = new.last, lastOld == lastNew {
            old.removeLast()
            new.removeLast()
        }
        let oldBase = "/" + old.joined(separator: "/")
        let newBase = "/" + new.joined(separator: "/")
        guard folderPath == oldBase || PathNormalizer.isComponentBoundaryDescendant(folderPath, of: oldBase) else {
            return nil
        }
        let below = folderPath.dropFirst(oldBase.count).drop { $0 == "/" }
        guard !below.isEmpty else { return newBase }
        return PathNormalizer.directoryPrefix(newBase) + below
    }
}

/// Finds files under one folder of a drive by their stored (NFC) relative paths, as the walk would read
/// them there: component by component through each directory's names, read once and kept for the songs
/// that follow (see the file header).
struct DriveLookup {
    let root: URL
    /// Each directory's entries already read, by directory path: name key → the names on the drive.
    private var listings: [String: Listing] = [:]
    /// Whether a walk goes into each directory already looked at, by path.
    private var walkable: [String: Bool] = [:]

    init(root: URL) {
        self.root = root
    }

    /// One directory's names, keyed two ways: by their stored (NFC) form, and by that form case-folded.
    private struct Listing {
        var exact: [String: String] = [:]
        var folded: [String: [String]] = [:]
    }

    /// Whether the root is a folder whose names can be read.
    var canReadRoot: Bool {
        mutating get { listing(of: root) != nil }
    }

    /// The file a walk would read for a song at `relativePath` under the root, of `size` bytes — nil when
    /// there is none.
    mutating func file(at relativePath: String, ofSize size: Int64) -> ScannedFile? {
        guard let url = locate(relativePath), !LibraryScanner.isHidden(url),
              case let .audio(scanned) = LibraryScanner.admit(fileURL: url, root: root),
              scanned.fileSize == size else { return nil }
        return scanned
    }

    /// The file at `relativePath` under the root, as the drive spells it, under folders a walk goes into —
    /// nil when there is none.
    private mutating func locate(_ relativePath: String) -> URL? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else { return nil }
        var directory = root
        for component in components.dropLast() {
            guard let spelled = entry(named: component, in: directory) else { return nil }
            directory = directory.appendingPathComponent(spelled, isDirectory: true)
            guard walkGoesInto(directory) else { return nil }
        }
        return entry(named: fileName, in: directory).map { directory.appendingPathComponent($0) }
    }

    /// The name in `directory` that is `name`: the same name (in the stored form), else the one name that
    /// differs from it only in letter case — nil when there is none, or several (a case-sensitive drive).
    private mutating func entry(named name: String, in directory: URL) -> String? {
        guard let listing = listing(of: directory) else { return nil }
        let key = PathNormalizer.normalizedComponent(name)
        if let exact = listing.exact[key] {
            return exact
        }
        guard let candidates = listing.folded[Self.folded(key)], candidates.count == 1 else { return nil }
        return candidates.first
    }

    /// `directory`'s names (read once per directory); nil when it can't be read.
    private mutating func listing(of directory: URL) -> Listing? {
        if let known = listings[directory.path] {
            return known
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        var listing = Listing()
        for name in names {
            let key = PathNormalizer.normalizedComponent(name)
            listing.exact[key] = name
            listing.folded[Self.folded(key), default: []].append(name)
        }
        listings[directory.path] = listing
        return listing
    }

    /// Whether a walk goes into `directory` (below the root): a real folder, not hidden, not a package, not a
    /// link, not another drive mounted there (`LibraryScanner.walk`'s enumerator options and mount rule).
    private mutating func walkGoesInto(_ directory: URL) -> Bool {
        if let known = walkable[directory.path] {
            return known
        }
        let goes = LibraryScanner.walkDescends(into: directory)
        walkable[directory.path] = goes
        return goes
    }

    /// A name's key for a letter-case-only match: its stored form, case-folded.
    private static func folded(_ key: String) -> String {
        key.folding(options: .caseInsensitive, locale: nil)
    }
}
