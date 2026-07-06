// LibraryScanner — the recursive scan → `LibraryStore` upsert + reconcile core (§2).
//
// A new SwiftPM library target `LibraryScan` (depends on `LibraryStore`), linked by
// BOTH the app and the harness so the walk has ONE implementation and never drifts.
// `supportedExtensions` is the SINGLE SOURCE OF TRUTH the app's `AudioFileEnumerator`
// references.
//
// S8.2a (produce-and-write core):
//   • one root per `scan` call → one per-root generation (M-A)
//   • walk via `FileManager.enumerator` reusing `[.skipsHiddenFiles,
//     .skipsPackageDescendants]`
//   • per file: guard regular-file + supported ext → build `ScannedFile` with the
//     full `(dev, inode, size, mtime)` move-signature (§3) → batch → `upsert`
//
// S8.2b (the reconciling half, added here):
//   • END-OF-WALK orphan sweep — `sweepOrphans(inFolders:[folderID], olderThan:gen)`
//     runs ONLY after the full walk completes (design §5, §9 D-sweep), so a re-scan
//     reconciles deletions. The sweep is ALWAYS single-root-scoped (M-A), so scanning
//     root B can never touch root A's rows.
//   • PROGRESS — an optional `@Sendable (ScanProgress) -> Void`, fired per committed
//     batch (indeterminate count-up, §5).
//   • CANCELLATION — `try Task.checkCancellation()` per file (cancels within one
//     file, §5). A cancelled scan leaves already-committed batches valid AND SKIPS
//     the sweep — no orphan is wrongly deleted from a partial view (this is why the
//     sweep is end-of-walk, not interleaved).
//
// Root-rejection (`validateNewRoot`) lives in RootValidation.swift; the caller runs
// it BEFORE `addRoot` + `scan` (design §6).

import Foundation
import LibraryStore

/// Recursively scans a registered root and reconciles its audio files into the store.
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

    /// The `(dev, inode)` on-disk identity of `url` (an `lstat`, symlinks unresolved) —
    /// the same signature `makeScannedFile` captures per file, exposed so a caller can
    /// hand a ROOT's identity to `LibraryStore.addRoot`, which treats a matching
    /// `(dev, inode)` as the same directory (case-insensitive-volume dedup, QS3).
    /// nil-tolerant: a failed `lstat` yields `(nil, nil)` and simply skips the dedup.
    public static func deviceInode(of url: URL) -> (dev: Int64?, inode: Int64?) {
        let signature = FileSignature.deviceInode(of: url)
        return (dev: signature.dev, inode: signature.inode)
    }

    /// Scan `root` (already `addRoot`'ed → `folderID`) and reconcile its subtree into
    /// `store`. Runs off the main actor (the caller wraps it in a detached task).
    ///
    /// Call flow (per root, design §2 + §5):
    ///   `let gen = try await store.beginScanGeneration()` (per-root, M-A) → walk →
    ///   per file `try Task.checkCancellation()`, guard regular-file + supported ext →
    ///   build `ScannedFile` → batch (~256) → `upsert` + fire `progress` → after the
    ///   FULL walk, `sweepOrphans(inFolders:[folderID], olderThan:gen)`.
    ///
    /// - Throws: `CancellationError` if the task is cancelled mid-walk (the sweep is
    ///   then skipped; committed batches stay valid); `RootUnreachableError` if the walk
    ///   saw ZERO files while the store still held rows for this root (the empty-walk
    ///   safety guard, S8.4 slice 3 — the sweep is refused, rows preserved); or whatever
    ///   `store` throws.
    /// - Returns: a `ScanResult` (generation, filesSeen, filesSkipped, orphansSwept,
    ///   trackIDs in walk order).
    public func scan(
        root: URL, folderID: Int64, into store: LibraryStore,
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanResult {
        let generation = try await store.beginScanGeneration()
        // Pre-scan magnitude for the empty-walk safety guard below.
        let preCount = try await store.trackCount(inFolder: folderID)
        let walked = try await walk(
            root: root, folderID: folderID, into: store,
            generation: generation, progress: progress
        )
        // EMPTY-WALK SAFETY GUARD (S8.4 slice 3, founder-approved "never wipe on an empty
        // walk"): if the walk enumerated ZERO files but the store held rows for this root,
        // REFUSE the sweep and throw — an unmounted/zombie-mounted volume or a deleted root
        // folder is indistinguishable from "every file deleted" via an empty walk, so
        // deletion must be positively evidenced by a successful non-empty walk, never
        // inferred from an empty one. The rows (and their user-state) are preserved; a later
        // reconcile of a reachable root reaps genuine deletions. A legitimately empty-but-
        // reachable root (preCount 0) still sweeps to a harmless no-op.
        if walked.filesSeen == 0, preCount > 0 {
            throw RootUnreachableError(folderID: folderID, storedRowCount: preCount)
        }
        // End-of-walk sweep (design §5, §9 D-sweep): reconciles deletions for THIS
        // root only. Reached ONLY after the walk completes — a cancellation throws in
        // `walk`, so a cancelled scan never sweeps (no wrongful delete). Single-root
        // scoped (M-A): never touches another root's rows.
        let orphansSwept = try await store.sweepOrphans(inFolders: [folderID], olderThan: generation)

        return ScanResult(
            generation: generation, filesSeen: walked.filesSeen,
            filesSkipped: walked.filesSkipped, orphansSwept: orphansSwept, trackIDs: walked.trackIDs
        )
    }

    // MARK: - Walk

    /// The accumulated result of walking a root: what a full traversal upserted.
    private struct WalkOutcome {
        var filesSeen = 0
        var filesSkipped = 0
        var trackIDs: [Int64] = []
    }

    /// Walk `root`, upserting supported files into `folderID` in ~`batchSize`
    /// batches, firing `progress` per committed batch. Checks cancellation PER FILE
    /// (§5) so a cancel is observed within one file; throwing here means the caller's
    /// end-of-walk sweep is skipped. Extracted from `scan` to keep both bodies within
    /// the function-length limit.
    private func walk(
        root: URL, folderID: Int64, into store: LibraryStore,
        generation: Int64, progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> WalkOutcome {
        var outcome = WalkOutcome()
        var batch: [ScannedFile] = []
        batch.reserveCapacity(Self.batchSize)

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(FileSignature.resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        if let enumerator {
            while let next = enumerator.nextObject() {
                // Cancel WITHIN one file (design §5): committed batches stay valid,
                // and the sweep in `scan` is skipped because this throws first.
                try Task.checkCancellation()
                guard let fileURL = next as? URL else { continue }
                guard let scanned = Self.makeScannedFile(fileURL: fileURL, root: root) else {
                    outcome.filesSkipped += 1
                    continue
                }
                outcome.filesSeen += 1
                batch.append(scanned)
                if batch.count >= Self.batchSize {
                    let ids = try await store.upsertReconciling(batch, folderID: folderID, generation: generation)
                    outcome.trackIDs.append(contentsOf: ids)
                    batch.removeAll(keepingCapacity: true)
                    progress?(ScanProgress(folderID: folderID, filesSeenSoFar: outcome.filesSeen))
                }
            }
        }

        // Flush the final partial batch + fire a closing progress tick.
        if !batch.isEmpty {
            let ids = try await store.upsertReconciling(batch, folderID: folderID, generation: generation)
            outcome.trackIDs.append(contentsOf: ids)
            progress?(ScanProgress(folderID: folderID, filesSeenSoFar: outcome.filesSeen))
        }
        return outcome
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
