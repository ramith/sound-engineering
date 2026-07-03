// ScanFixtureBuilder — writes a REAL temp-dir tree for the S8.2a scan cases (§8).
//
// The S8.1 cases assert against SYNTHETIC rows; S8.2 must scan ACTUAL files, so
// this builds a genuine directory tree under `test-data/scan-fixtures/<uuid>/` and
// hands the scanner the real root. Files are TINY but NON-EMPTY (design §8): S8.2
// reads FS attributes only, but an empty file would make S8.3's future metadata
// probe brittle, so every leaf gets a few bytes.
//
// It also exposes `independentLstat` — a fresh `lstat` of a real file used by the
// signature case to prove the scanner stored the REAL `(size, mtime, inode, dev)`,
// not a fabricated value (a scanner stamping `now` for mtime, or the same inode for
// two files, is caught).
//
// Cleanup mirrors the harness idiom: the run's whole scan-fixture directory is
// removed on overall success (kept on failure for post-mortem); a `chmod`ed dir is
// restored to writable before removal so teardown never fails.

import Foundation

// MARK: - Scan-fixture root management

/// The per-run scan-fixture root: `test-data/scan-fixtures/<runIdentifier>/`. All
/// scan cases build their trees under here; the whole directory is torn down on
/// overall success by `cleanupScanFixtures()`.
let scanFixtureRoot: URL = {
    let directory = testDataDirectory
        .appendingPathComponent("scan-fixtures", isDirectory: true)
        .appendingPathComponent(runIdentifier, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}()

/// Remove this run's entire scan-fixture tree. Restores any read-only directory to
/// writable first so a `chmod`ed permission-denied fixture (S8.2b) can still be
/// deleted; a best-effort no-op if the tree is absent.
func cleanupScanFixtures() {
    let fileManager = FileManager.default
    restoreWritableRecursively(scanFixtureRoot)
    try? fileManager.removeItem(at: scanFixtureRoot)
}

/// Recursively restore write+execute permission on every directory under `url` so a
/// `chmod 0o000` fixture cannot wedge teardown. Best-effort.
private func restoreWritableRecursively(_ url: URL) {
    let fileManager = FileManager.default
    try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    guard let entries = try? fileManager.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
    ) else { return }
    for entry in entries {
        let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            restoreWritableRecursively(entry)
        }
    }
}

// MARK: - Tree builder

/// Builds real directory trees for the scan cases.
enum ScanFixtureBuilder {
    /// Create a fresh, uniquely-named case directory under the run's scan-fixture
    /// root and return it. `label` keeps failures individually identifiable.
    static func makeCaseRoot(_ label: String) throws -> URL {
        let root = scanFixtureRoot.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Create a directory at `root/relativeComponents…` (each element one path
    /// component) and return its URL. Intermediate directories are created.
    @discardableResult
    static func makeDirectory(at root: URL, _ components: [String]) throws -> URL {
        var directory = root
        for component in components {
            directory = directory.appendingPathComponent(component, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Write a TINY NON-EMPTY file named `fileName` under `root/subdirs…`, returning
    /// its URL. `byteCount` bytes (default 8) of deterministic filler are written so
    /// the file is never zero-length (design §8). Parent directories are created.
    @discardableResult
    static func writeFile(
        at root: URL, subdirs: [String] = [], fileName: String, byteCount: Int = 8
    ) throws -> URL {
        let directory = subdirs.isEmpty ? root : try makeDirectory(at: root, subdirs)
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        let bytes = Data((0 ..< byteCount).map { UInt8($0 & 0xFF) })
        try bytes.write(to: fileURL)
        return fileURL
    }

    /// Copy `source` to `destination` (a real second file → a DISTINCT inode), returning
    /// `destination`. For the copy-is-not-a-move case (S8.4 M11). Parent dirs must exist.
    @discardableResult
    static func copyFile(from source: URL, to destination: URL) throws -> URL {
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Overwrite the file at `url` with `byteCount` bytes of DIFFERENT filler — changes
    /// size (and mtime), i.e. a content modification at the SAME path (S8.4 M10). The
    /// byte pattern is distinct from `writeFile`'s so the content genuinely differs.
    static func overwriteFile(at url: URL, byteCount: Int) throws {
        let bytes = Data((0 ..< byteCount).map { UInt8((0xFF - $0) & 0xFF) })
        try bytes.write(to: url)
    }

    /// The nested tree the scan-correctness case asserts against. Returns the root
    /// plus the set of audio-file URLs that SHOULD end up as rows (so the case can
    /// assert an EXACT match, not just a count). The tree deliberately contains:
    ///   • mixed audio extensions across nested subdirs (case-insensitive: `.FLAC`),
    ///   • non-audio files (`.txt`, `.jpg`, `.cue`) that must be excluded,
    ///   • a hidden dotfile + a hidden `.dir/` that must be excluded,
    ///   • a DIRECTORY named `music.mp3/` (with an audio file inside it) that must
    ///     NOT be treated as a leaf — its inner file IS a normal row, but the
    ///     directory itself never becomes one.
    static func buildNestedTree(_ root: URL) throws -> Set<String> {
        var expected = Set<String>()
        func expect(_ url: URL) {
            expected.insert(url.path)
        }

        // Root-level audio + a non-audio sibling.
        expect(try writeFile(at: root, fileName: "root-song.flac"))
        _ = try writeFile(at: root, fileName: "notes.txt")
        _ = try writeFile(at: root, fileName: "cover.jpg")

        // Nested subdirs with mixed (case-insensitive) audio extensions.
        expect(try writeFile(at: root, subdirs: ["Sub"], fileName: "a.mp3"))
        expect(try writeFile(at: root, subdirs: ["Sub", "Deep"], fileName: "b.FLAC"))
        expect(try writeFile(at: root, subdirs: ["Sub", "Deep"], fileName: "c.m4a"))
        _ = try writeFile(at: root, subdirs: ["Sub", "Deep"], fileName: "playlist.cue")

        // Hidden dotfile + hidden directory — both excluded by .skipsHiddenFiles.
        _ = try writeFile(at: root, fileName: ".hidden-song.flac")
        _ = try writeFile(at: root, subdirs: [".hidden-dir"], fileName: "inside-hidden.flac")

        // A DIRECTORY literally named `music.mp3` — must not be scanned as a leaf,
        // but an audio file INSIDE it is a normal row.
        expect(try writeFile(at: root, subdirs: ["music.mp3"], fileName: "inner.wav"))

        return expected
    }
}

// MARK: - Independent lstat (signature ground truth)

/// A fresh, scanner-independent `lstat` of a real file: the ground-truth
/// `(size, mtime, inode, dev)` the signature case compares each stored row against.
/// Whole-second mtime (matches the schema discipline). `nil` if the `lstat` fails.
struct IndependentSignature: Equatable {
    let size: Int64
    let mtime: Int64
    let inode: Int64
    let dev: Int64
}

/// Read `(size, mtime, inode, dev)` straight from the filesystem for `fileURL`,
/// bypassing the scanner entirely. `lstat` (not `stat`) so a symlink is its own
/// entry, matching the scanner's policy.
func independentLstat(_ fileURL: URL) -> IndependentSignature? {
    var info = stat()
    let result = fileURL.withUnsafeFileSystemRepresentation { pointer -> Int32 in
        guard let pointer else { return -1 }
        return lstat(pointer, &info)
    }
    guard result == 0 else { return nil }
    return IndependentSignature(
        size: Int64(info.st_size),
        mtime: Int64(info.st_mtimespec.tv_sec),
        inode: Int64(info.st_ino),
        dev: Int64(info.st_dev)
    )
}
