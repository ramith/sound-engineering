// LibraryScanner — the recursive scan → `LibraryStore` upsert + reconcile core (§2).
//
// A new SwiftPM library target `LibraryScan` (depends on `LibraryStore`), linked by
// BOTH the app and the harness so the walk has ONE implementation and never drifts.
// `supportedExtensions` is the SINGLE SOURCE OF TRUTH for which files a walk admits.
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
// R1 (council P5A-01/02) — a sweep needs POSITIVE evidence that what it deletes is gone; else the
// scan throws `SweepRefusal` (SweepRefusal.swift has the reasons):
//   • THE ROOT'S OWN DRIVE — the root is walked only when it is there, on the drive it is bound to (an
//     unbound root: only when some of its songs are where the library has them), and only while it
//     stays that same directory on that same drive — checked before every batch is committed, so a
//     drive swapped under the walk adds at most nothing more. Only then is an unbound root bound
//     (`LibraryStore.restampRoot`). The identity is read through a seam (`init(rootIdentity:)`). The
//     check before a walk (`rootAtPath`) is also what a song's absence is judged by: a song is MISSING
//     only when its folder passes it (`availability(of:in:)`, FileAvailability.swift — KI-LIB-01).
//   • EVIDENCE OF WHAT IT READ — a walk is evidence only for what it could read. A folder the enumerator
//     could not open, or an audio file that is there but can't be read, is no evidence of what is gone
//     under it: the sweep SPARES every row at or under such a path, and reaps the rest of the root as
//     usual (R1.1-A, council C-55 — one permanently unreadable subfolder, a NAS's locked `#recycle`,
//     used to stop every sweep of its root and, with the refusal, the root's tag pass). A walk that
//     could not read the root itself, or saw nothing at all (S8.4 slice 3), is evidence of nothing: it
//     still commits what it found, and refuses the sweep when it would delete anything.
//   • ONE DRIVE PER ROOT — a volume mounted inside the root is never walked (`walk`).
//
// Root-rejection (`validateNewRoot`) lives in RootValidation.swift; the caller runs
// it BEFORE `addRoot` + `scan` (design §6).

import Foundation
import LibraryStore

/// Recursively scans a registered root and reconciles its audio files into the store.
public struct LibraryScanner: Sendable {
    /// The audio container extensions a scan admits (lowercased) — the SINGLE
    /// SOURCE OF TRUTH for which files reach the library (design §2). AVAudioFile and
    /// ExtAudioFile natively open these on macOS, so none needs FFmpeg. "aif" is the spelling
    /// Music, iTunes and Logic give every AIFF they write (S10.8 G, G-LIB-02); "opus" and "oga"
    /// are Ogg Opus and Ogg Vorbis, which Apple's decoder opens on macOS 26 (R1.1-A, council
    /// C-08, KI-LIB-05). The format table test opens a real file of every kind listed here.
    public static let supportedExtensions: Set<String> = [
        "flac", "mp3", "wav", "aac", "m4a", "alac", "aiff", "aif", "ogg", "oga", "opus",
    ]

    /// Rows accumulated before a batch `upsert` (one `BEGIN IMMEDIATE…COMMIT` each).
    /// An INTERNAL constant, not public API (design §2 O-1): bounds transaction
    /// size + keeps each actor hop short so a long scan does not starve S9 reads.
    private static let batchSize = 256

    /// Reads what is at a root's path now — nil when it is not reachable. The real filesystem by default
    /// (`RootReachabilityProbe.identity(of:)`); a seam, so a test can stand in a drive that is swapped,
    /// or goes away, under a walk without mounting one.
    private let rootIdentity: @Sendable (URL) -> RootIdentity?

    public init(rootIdentity: @escaping @Sendable (URL) -> RootIdentity? = RootReachabilityProbe.identity(of:)) {
        self.rootIdentity = rootIdentity
    }

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
    /// Call flow (per root, design §2 + §5, R1):
    ///   `let gen = try await store.beginScanGeneration()` (per-root, M-A) → read the root's identity
    ///   and check its drive (bound: the same drive; unbound: some of its songs where they were) →
    ///   walk → per file `try Task.checkCancellation()`, guard regular-file + supported ext → build
    ///   `ScannedFile` → batch (~256) → the root unchanged → `upsert` + fire `progress` → after the FULL
    ///   walk, the root still the one walked → bind + re-stamp it (`restampRoot`) →
    ///   `sweepOrphans(inFolders:[folderID], olderThan:gen, sparing:)`, given positive evidence — of
    ///   all but what it could not read.
    ///
    /// - Throws: `CancellationError` if the task is cancelled mid-walk (the sweep is
    ///   then skipped; committed batches stay valid); `SweepRefusal` when the walk is not evidence of
    ///   which of the root's songs are gone — the root is not there, is on another drive or is
    ///   unrecognized (not walked), it changed under the walk (stopped), or the walk could not read the
    ///   root or saw nothing while the sweep would delete something (rows preserved); or whatever
    ///   `store` throws. What it could not read BELOW the root is spared, not refused (C-55).
    /// - Returns: a `ScanResult` (generation, filesSeen, filesSkipped, orphansSwept,
    ///   trackIDs in walk order).
    public func scan(
        root: URL, folderID: Int64, into store: LibraryStore,
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanResult {
        let generation = try await store.beginScanGeneration()
        let preCount = try await store.trackCount(inFolder: folderID)
        func refusal(_ reason: SweepRefusal.Reason) -> SweepRefusal {
            SweepRefusal(folderID: folderID, reason: reason, storedRowCount: preCount)
        }
        // THE ROOT'S OWN DRIVE: walk the root only when it is there, on its own drive (`rootAtPath`).
        let identity: RootIdentity
        switch try await rootAtPath(root, folderID: folderID, in: store) {
        case let .own(own): identity = own
        case let .refused(reason): throw refusal(reason)
        }
        let walked = try await walk(
            root: root, as: identity,
            into: WalkTarget(store: store, folderID: folderID, generation: generation), progress: progress
        )
        // The walk is evidence only of the root it began on — not of one that went away under it, or of
        // another drive mounted at its path meanwhile (the walk stopped at the first batch after).
        if let reason = walked.rootChange ?? change(of: root, since: identity) {
            throw refusal(reason)
        }
        // Confirmed: bind an unbound root to this drive, and refresh its (dev, inode).
        guard try await store.restampRoot(id: folderID, to: identity) else { throw refusal(.differentVolume) }
        // End-of-walk sweep (design §5, §9 D-sweep): reconciles deletions for THIS root only (M-A),
        // reached ONLY after the walk completes (a cancellation throws in `walk`), sparing the rows under
        // what the walk could not read (C-55). A walk that could not read the root itself, or saw nothing
        // (S8.4 slice 3, founder-approved "never wipe on an empty walk"), is not evidence that what it
        // missed is gone: no sweep — refused when it would delete.
        let orphansSwept: Int
        if let reason = walked.missingEvidence {
            let unseen = try await store.orphanCount(inFolders: [folderID], olderThan: generation,
                                                     sparing: walked.unreadable)
            guard unseen == 0 else { throw refusal(reason) }
            orphansSwept = 0
        } else {
            orphansSwept = try await store.sweepOrphans(inFolders: [folderID], olderThan: generation,
                                                        sparing: walked.unreadable)
        }

        return ScanResult(
            generation: generation, filesSeen: walked.filesSeen,
            filesSkipped: walked.filesSkipped, orphansSwept: orphansSwept, trackIDs: walked.trackIDs
        )
    }

    /// How the root changed since the walk read `start`: gone from its path, on another volume, or
    /// another directory there (replaced, or its volume remounted). nil when it is the same.
    private func change(of root: URL, since start: RootIdentity) -> SweepRefusal.Reason? {
        guard let now = rootIdentity(root) else { return .rootVanished }
        guard now.volume == start.volume else { return .differentVolume }
        return now == start ? nil : .rootVanished
    }

    /// What a walk of a root finds at its path before it starts.
    enum RootAtPath {
        /// The root's own directory, on its own drive: walk it.
        case own(RootIdentity)
        /// Not the root's own: the walk is refused, for this reason.
        case refused(SweepRefusal.Reason)
    }

    /// What is at `root`'s path now (R1): its own directory when it is there, on the drive it is bound
    /// to — or, unbound, when some of its songs are where the library has them (a stale folder or
    /// another drive at its path holds none, and walking it would leave rows that vouch for it next
    /// time). Otherwise why a walk is refused: it is not there, it is on another drive, or it is
    /// unrecognized. The check `scan` makes first — and the one a song's absence is judged by
    /// (`availability(of:in:)`).
    func rootAtPath(_ root: URL, folderID: Int64, in store: LibraryStore) async throws -> RootAtPath {
        guard let identity = rootIdentity(root) else { return .refused(.rootVanished) }
        if let bound = try await store.boundVolume(ofRoot: folderID) {
            return bound == identity.volume ? .own(identity) : .refused(.differentVolume)
        }
        return try await holdsNoneOfItsSongs(folderID, in: store) ? .refused(.unrecognizedFolder) : .own(identity)
    }

    /// Whether `folderID` has songs and none of them is where the library has it — then the folder at an
    /// UNBOUND root's path is not shown to be the root's own. A root with no songs has nothing to lose.
    /// Looks page by page and stops at the first song found, so a folder that is the root's costs a look
    /// or two; one that holds none of them costs a look per song, and is then not walked.
    private func holdsNoneOfItsSongs(_ folderID: Int64, in store: LibraryStore) async throws -> Bool {
        var afterID: Int64 = 0
        while true {
            let page = try await store.trackURLs(inFolder: folderID, afterID: afterID, limit: Self.batchSize)
            guard let last = page.last else { return afterID != 0 }
            if page.contains(where: { FileSignature.deviceInode(of: $0.url).inode != nil }) {
                return false
            }
            afterID = last.id
        }
    }

    // MARK: - Walk

    /// Where a walk writes: the store, the root's folder row, and the walk's generation.
    private struct WalkTarget {
        let store: LibraryStore
        let folderID: Int64
        let generation: Int64
    }

    /// The accumulated result of walking a root: what a full traversal upserted, and what it could
    /// not read.
    private struct WalkOutcome {
        var filesSeen = 0
        var filesSkipped = 0
        /// What below the root the walk could not read: a folder the enumerator reported it could not
        /// open (or that failed under it), an audio file that is there but could not be read. The sweep
        /// spares every row at or under these (C-55).
        var unreadable: [URL] = []
        /// The walk could not read the root itself: it is evidence of nothing.
        var rootUnreadable = false
        /// How the root changed under the walk, seen before a batch was committed: the walk stopped.
        var rootChange: SweepRefusal.Reason?
        var trackIDs: [Int64] = []

        /// Why this walk is not evidence that the songs it did not see are gone — nil when it is.
        var missingEvidence: SweepRefusal.Reason? {
            if rootUnreadable {
                return .incompleteWalk
            }
            return filesSeen == 0 ? .emptyWalk : nil
        }

        /// Count one enumerated entry at `url`; the file to upsert, if it is one.
        mutating func record(_ admission: Admission, at url: URL) -> ScannedFile? {
            switch admission {
            case let .audio(scanned):
                filesSeen += 1
                return scanned
            case .unreadable:
                unreadable.append(url)
            case .skipped:
                break
            }
            filesSkipped += 1
            return nil
        }

        /// What the enumerator could not read: the root itself, or a path below it.
        mutating func recordUnreadable(_ urls: [URL], root: URL) {
            let rootKey = PathNormalizer.normalizedString(for: root)
            for url in urls {
                if PathNormalizer.normalizedString(for: url) == rootKey {
                    rootUnreadable = true
                } else {
                    unreadable.append(url)
                }
            }
        }
    }

    /// Walk `root`, upserting supported files into `folderID` in ~`batchSize`
    /// batches, firing `progress` per committed batch. Checks cancellation PER FILE
    /// (§5) so a cancel is observed within one file; throwing here means the caller's
    /// end-of-walk sweep is skipped. Extracted from `scan` to keep both bodies within
    /// the function-length limit.
    ///
    /// What it could NOT read (R1, scoped by C-55): with no error handler the enumerator skips what it
    /// cannot read and says nothing (Apple: a nil errorHandler "continues to enumerate items as if you
    /// had specified a block that returned true"). Every error's path is recorded, and the walk goes on
    /// (true) so it still sees all it can. ONE DRIVE PER ROOT: Apple documents that the enumerator
    /// traverses a mount point — another volume mounted inside the root — though on macOS 26 the URL
    /// enumerator was seen not to. Either way it is skipped here: the root's drive is the walk's
    /// evidence (`scan`), and songs on a drive that comes and goes inside the root would be swept
    /// whenever it is away. Before each batch is committed the root must still be `identity` — a drive
    /// swapped or gone under the walk stops it.
    private func walk(
        root: URL, as identity: RootIdentity, into target: WalkTarget,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> WalkOutcome {
        var outcome = WalkOutcome()
        var batch: [ScannedFile] = []
        batch.reserveCapacity(Self.batchSize)

        var enumerationErrors: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(FileSignature.walkKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in
                enumerationErrors.append(url)
                return true
            }
        )

        /// Commit the batch and fire a progress tick — unless the root changed since the walk began:
        /// then it commits nothing, records the change and returns false (the walk stops).
        func commit() async throws -> Bool {
            if let change = change(of: root, since: identity) {
                outcome.rootChange = change
                return false
            }
            let ids = try await target.store.upsertReconciling(
                batch, folderID: target.folderID, generation: target.generation
            )
            outcome.trackIDs.append(contentsOf: ids)
            batch.removeAll(keepingCapacity: true)
            progress?(ScanProgress(folderID: target.folderID, filesSeenSoFar: outcome.filesSeen))
            return true
        }

        if let enumerator {
            while let next = enumerator.nextObject() {
                // Cancel WITHIN one file (design §5): committed batches stay valid,
                // and the sweep in `scan` is skipped because this throws first.
                try Task.checkCancellation()
                guard let fileURL = next as? URL else { continue }
                if FileSignature.isMountPoint(fileURL) {
                    enumerator.skipDescendants()
                }
                guard let scanned = outcome.record(Self.admit(fileURL: fileURL, root: root), at: fileURL) else {
                    continue
                }
                batch.append(scanned)
                if batch.count >= Self.batchSize, try await !commit() {
                    break
                }
            }
        }

        // Commit the final partial batch (a stopped walk commits nothing more).
        if !batch.isEmpty, outcome.rootChange == nil {
            _ = try await commit()
        }
        outcome.recordUnreadable(enumerator == nil ? [root] : enumerationErrors, root: root)
        return outcome
    }

    // MARK: - Per-file → ScannedFile

    /// What a walk makes of one enumerated entry.
    enum Admission {
        /// A supported audio file that is there: upserted, and seen.
        case audio(ScannedFile)
        /// Not an audio file: a directory (a `music.mp3/` one too), another extension, a symlink.
        case skipped
        /// A listed audio file the walk could not read, or find there any more: the sweep spares it.
        case unreadable
    }

    /// Build a `ScannedFile` for `fileURL` under `root`, or `nil` to SKIP it
    /// (a directory — including a `music.mp3/` directory — an unsupported
    /// extension, or an unreadable/vanished file: a TOCTOU skip, never a crash,
    /// design §8; a walk counts the last kind as unreadable, `admit`). Preserves
    /// `AudioFileEnumerator`'s `try?`-skip discipline.
    /// `public` so the headless harness (a separate target) can read a single file's
    /// scan signature for `classify` assertions (the swift-test-is-broken harness boundary).
    public static func makeScannedFile(fileURL: URL, root: URL) -> ScannedFile? {
        guard case let .audio(scanned) = admit(fileURL: fileURL, root: root) else { return nil }
        return scanned
    }

    /// Admit `fileURL` under `root` — the walk's per-entry decision, which `makeScannedFile` exposes.
    /// The extension is checked first (no I/O). A listed audio file is admitted only when it is there:
    /// its attributes read AND its `lstat` succeeds (prefetched attributes outlive a file, or a drive,
    /// gone since the listing). Otherwise it is UNREADABLE, and its row is spared — even for a file
    /// deleted since it was listed: "not found" is no evidence when its drive may be what went (a drive
    /// that went stops the walk anyway), and the next walk, which no longer lists it, is.
    static func admit(fileURL: URL, root: URL) -> Admission {
        guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
            return .skipped
        }
        // ONE resourceValues fetch (§3).
        guard let attributes = FileSignature.attributes(of: fileURL) else {
            return .unreadable
        }
        guard attributes.isRegularFile else {
            return .skipped
        }
        // ONE lstat for st_ino AND st_dev (§3, M-B) — and the proof the file is there.
        let signature = FileSignature.deviceInode(of: fileURL)
        guard signature.inode != nil else {
            return .unreadable
        }
        let name = fileURL.deletingPathExtension().lastPathComponent
        let format = fileURL.pathExtension.uppercased()
        let relativePath = RelativePathResolver.relativePath(forFile: fileURL, root: root)

        return .audio(ScannedFile(
            url: fileURL,
            relativePath: relativePath,
            name: name,
            format: format,
            fileSize: attributes.fileSize,
            mtime: attributes.mtime,
            inode: signature.inode,
            dev: signature.dev
        ))
    }
}
