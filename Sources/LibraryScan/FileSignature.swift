// FileSignature — the per-file filesystem read that builds a `ScannedFile` (§3).
//
// S8.2a. ONE `URLResourceValues` fetch (`.isRegularFileKey`, `.fileSizeKey`,
// `.contentModificationDateKey`) + ONE `lstat` for the real `st_ino` AND `st_dev`
// (M-B). Together these give the full move-signature `(dev, inode, size, mtime)`
// that S8.4 matches to follow external moves — populated now, matched later.
//
// Discipline (design §3):
//   • `mtime = Int64(contentModificationDate.timeIntervalSince1970)` — WHOLE
//     seconds, matching the schema + `LibraryStore.nowSeconds()`.
//   • `lstat` (NOT `stat`) — a symlink keeps its own distinct entry, consistent
//     with `PathNormalizer`'s no-resolve policy.
//   • `inode`/`dev` are nil-tolerant: a failed `lstat` yields nil for both. A WALK no
//     longer admits such a file, though (R1, sweep evidence): the enumerator's prefetched
//     attributes outlive a file — or a whole drive — gone since it was listed, so the
//     `lstat` is the walk's proof the file is there (`LibraryScanner.admit`).
//   • `URLResourceValues` has no inode field, and `.fileResourceIdentifierKey` is
//     opaque/non-persistable — hence the explicit `lstat`.

import Foundation

/// Reads a file's move-signature from disk into the pieces of a `ScannedFile`.
enum FileSignature {
    /// The `st_ino`/`st_dev` pair from a single `lstat` (nil-tolerant).
    struct DeviceInode {
        let inode: Int64?
        let dev: Int64?
    }

    /// The regular-file flag + size + whole-second mtime from ONE resource fetch.
    /// `nil` when the fetch fails (the file vanished between enumerate and stat — a
    /// TOCTOU skip, design §8 — or is otherwise unreadable).
    struct Attributes {
        let isRegularFile: Bool
        let fileSize: Int64
        let mtime: Int64
    }

    /// The resource keys fetched once per file.
    static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
    ]

    /// The keys a walk's enumerator prefetches per entry: a file's `resourceKeys`, and whether a
    /// directory is the root of a mounted volume (`isMountPoint`).
    static let walkKeys: Set<URLResourceKey> = resourceKeys.union([.isVolumeKey])

    /// Fetch the attributes for `fileURL` in one `resourceValues` call, or `nil` if
    /// the file could not be read (skipped, never a crash).
    static func attributes(of fileURL: URL) -> Attributes? {
        guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
            return nil
        }
        let isRegular = values.isRegularFile ?? false
        let size = Int64(values.fileSize ?? 0)
        // Whole seconds — matches the mtime schema discipline (design §3).
        let mtime: Int64
        if let modified = values.contentModificationDate {
            mtime = Int64(modified.timeIntervalSince1970)
        } else {
            mtime = 0
        }
        return Attributes(isRegularFile: isRegular, fileSize: size, mtime: mtime)
    }

    /// One `lstat` for the real `st_ino` and `st_dev`. Symlinks are NOT resolved
    /// (`lstat`), so a symlink stays its own entry. A failed `lstat` → both nil.
    static func deviceInode(of fileURL: URL) -> DeviceInode {
        guard case let .found(info) = lstatResult(of: fileURL) else {
            return DeviceInode(inode: nil, dev: nil)
        }
        return DeviceInode(inode: Int64(info.st_ino), dev: Int64(info.st_dev))
    }

    /// Whether nothing is at `url`'s path: its `lstat` fails because the file, or a folder on its path,
    /// does not exist (ENOENT / ENOTDIR). A path the app may not look into (EACCES), a failing drive
    /// (EIO) or a dangling link is NOT absent: what is there is unknown.
    static func isAbsent(_ url: URL) -> Bool {
        guard case let .failed(code) = lstatResult(of: url) else { return false }
        return code == ENOENT || code == ENOTDIR
    }

    /// What one `lstat` of a path found.
    private enum LStat {
        case found(stat)
        case failed(errno: Int32)
    }

    /// `lstat` over the null-terminated fs representation — never resolves symlinks.
    private static func lstatResult(of url: URL) -> LStat {
        var info = stat()
        let code = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { return ENOENT }
            return lstat(pointer, &info) == 0 ? 0 : errno
        }
        return code == 0 ? .found(info) : .failed(errno: code)
    }

    /// Whether `url` is the root of a mounted volume (another drive mounted inside a walked folder).
    /// Read from the enumerator's prefetched `walkKeys`.
    static func isMountPoint(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isVolumeKey]).isVolume) == true
    }
}
