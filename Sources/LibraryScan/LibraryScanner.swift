// LibraryScanner — the recursive scan → `LibraryStore` upsert core (design §2).
//
// S8.2a (produce-and-write core). A new SwiftPM library target `LibraryScan`
// (depends on `LibraryStore`), linked by BOTH the app and the harness so the walk
// has ONE implementation and never drifts. `supportedExtensions` is the SINGLE
// SOURCE OF TRUTH the app's `AudioFileEnumerator` references.
//
// Scope of THIS chunk (S8.2a):
//   • one root per `scan` call → one per-root generation (M-A)
//   • walk via `FileManager.enumerator` reusing the app's
//     `[.skipsHiddenFiles, .skipsPackageDescendants]` options
//   • per file: guard regular-file + supported ext → build `ScannedFile` with the
//     full `(dev, inode, size, mtime)` move-signature (§3) → batch → `upsert`
//   • returns a `ScanResult`
//
// DEFERRED to S8.2b (marked below): the end-of-walk orphan sweep (re-scan
// reconciliation), progress callback, cancellation checks, and the VM seam. This
// core does NOT sweep, so a re-scan here only inserts/updates — deletions are
// reconciled in S8.2b.

import Foundation
import LibraryStore

/// Recursively scans a registered root and upserts its audio files into the store.
public struct LibraryScanner: Sendable {
    /// The audio container extensions a scan admits (lowercased) — the SINGLE
    /// SOURCE OF TRUTH shared with the app's `AudioFileEnumerator`, so the two
    /// walks can never diverge (design §2). AVAudioFile natively supports these on
    /// macOS.
    public static let supportedExtensions: Set<String> = [
        "flac", "mp3", "wav", "aac", "m4a", "alac", "aiff", "ogg",
    ]

    /// Rows accumulated before a batch `upsert` (one `BEGIN IMMEDIATE…COMMIT` each).
    /// An INTERNAL constant, not public API (design §2 O-1): bounds transaction
    /// size + keeps each actor hop short so a long scan does not starve S9 reads.
    private static let batchSize = 256

    public init() {}

    /// Scan `root` (already `addRoot`'ed → `folderID`) and upsert its subtree into
    /// `store`. Runs off the main actor (the caller wraps it in a detached task).
    ///
    /// Call flow (per root, design §2):
    ///   `let gen = try await store.beginScanGeneration()` → walk → per file guard
    ///   regular-file + supported ext → build `ScannedFile` → batch (~256) →
    ///   `try await store.upsert(batch, folderID:generation:)`.
    ///
    /// `beginScanGeneration()` is called ONCE here (per-root generation, M-A);
    /// S8.2a scans exactly one root per call.
    ///
    /// NO orphan sweep in S8.2a — the re-scan reconciliation sweep is S8.2b.
    ///
    /// - Throws: whatever `store` throws (a write error propagates).
    /// - Returns: a `ScanResult` (folderID, generation, filesSeen, filesSkipped,
    ///   trackIDs in walk order).
    public func scan(root: URL, folderID: Int64, into store: LibraryStore) async throws -> ScanResult {
        let generation = try await store.beginScanGeneration()

        var batch: [ScannedFile] = []
        batch.reserveCapacity(Self.batchSize)
        var trackIDs: [Int64] = []
        var filesSeen = 0
        var filesSkipped = 0

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(FileSignature.resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        if let enumerator {
            while let next = enumerator.nextObject() {
                // S8.2b: Task.checkCancellation() goes here (per file, not per batch).
                guard let fileURL = next as? URL else { continue }
                guard let scanned = Self.makeScannedFile(fileURL: fileURL, root: root) else {
                    filesSkipped += 1
                    continue
                }
                filesSeen += 1
                batch.append(scanned)
                if batch.count >= Self.batchSize {
                    let ids = try await store.upsert(batch, folderID: folderID, generation: generation)
                    trackIDs.append(contentsOf: ids)
                    batch.removeAll(keepingCapacity: true)
                }
            }
        }

        // Flush the final partial batch.
        if !batch.isEmpty {
            let ids = try await store.upsert(batch, folderID: folderID, generation: generation)
            trackIDs.append(contentsOf: ids)
        }

        // S8.2b: end-of-walk sweepOrphans(inFolders:[folderID], olderThan:generation)
        // (re-scan reconciliation) goes here — deliberately absent in S8.2a.

        return ScanResult(
            folderID: folderID, generation: generation, filesSeen: filesSeen,
            filesSkipped: filesSkipped, trackIDs: trackIDs
        )
    }

    // MARK: - Per-file → ScannedFile

    /// Build a `ScannedFile` for `fileURL` under `root`, or `nil` to SKIP it
    /// (a directory — including a `music.mp3/` directory — an unsupported
    /// extension, or an unreadable/vanished file: a TOCTOU skip, never a crash,
    /// design §8). Preserves `AudioFileEnumerator`'s `try?`-skip discipline.
    /// `public` so the headless harness (a separate target) can read a single file's
    /// scan signature for `classify` assertions (the swift-test-is-broken harness boundary).
    public static func makeScannedFile(fileURL: URL, root: URL) -> ScannedFile? {
        // ONE resourceValues fetch (§3). A failed fetch (file vanished) → skip.
        guard let attributes = FileSignature.attributes(of: fileURL),
              attributes.isRegularFile else {
            return nil
        }
        let ext = fileURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return nil
        }
        // ONE lstat for st_ino AND st_dev (§3, M-B); nil-tolerant.
        let signature = FileSignature.deviceInode(of: fileURL)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let format = fileURL.pathExtension.uppercased()
        let relativePath = RelativePathResolver.relativePath(forFile: fileURL, root: root)

        return ScannedFile(
            url: fileURL,
            relativePath: relativePath,
            name: name,
            format: format,
            fileSize: attributes.fileSize,
            mtime: attributes.mtime,
            inode: signature.inode,
            dev: signature.dev
        )
    }
}
