// MetadataScanner — the S8.3 background metadata pass (design §6).
//
// Enriches tracks that still need metadata (metadata_scanned == 0). Extraction (file
// read + parse + thumbnail) is CPU/IO-bound and runs OFF the actor in a CONTINUOUSLY-
// REFILLED bounded pool (a sliding window of at most `maxInFlight` extractions, sized to
// the M1→M5 core profile); the store WRITES serialize on the actor (one
// applyExtractedResult transaction per track). Triggered after the structural scan (NOT
// inline), reusing the scan's generation — or alone, at launch, for songs left pending (the
// one-time re-read of a derived-data bump, or a pass cut off at quit). FS-tolerant: a file that
// is there but can't be parsed is marked (anti-loop), while a file that is NOT there — moved
// away, its volume unmounted — stays PENDING, so it is read when it comes back (S10.8 C2 fix
// round, B1: marking it would spend its one re-read on nothing). Cancellable (per-task +
// post-apply checkCancellation; a cancelled pass SKIPS the end-of-pass steps — no wrongful file
// delete on a partial view). A song whose row disappears mid-pass (its folder removed) is skipped.
//
// The end of every clean pass derives what the whole library implies (S10.8 C2): regroup every
// song's album — the AUTHORITY, since the pass's own writes do no album work (fix round B2) —
// and reap orphan facets, THEN sweep orphan artwork, so art a reaped album held is reclaimed in
// the same pass. It runs even when no song was pending: a scan that only deleted files still
// changes albums, and a pass cut off at quit leaves its regroup owed to the next one.

import Foundation
import LibraryStore

public struct MetadataScanner: Sendable {
    /// A per-track extraction result crossing back from the concurrent pool (Sendable).
    private struct ExtractResult {
        let trackID: Int64
        let outcome: Outcome
    }

    /// What reading one pending song found.
    private enum Outcome {
        /// Tags (and maybe art) were read → write them and mark the song scanned.
        case read(TrackMetadata, ArtworkLink?)
        /// The file is there but can't be parsed → mark it scanned, so it is never retried
        /// (anti-loop).
        case unreadable
        /// The file is not there (moved away, volume unmounted) → leave it pending (B1).
        case offline
        /// The song's row was deleted since the pending snapshot → nothing to do.
        case gone
    }

    /// `tracksNeedingMetadata` limit meaning "no limit" — the pass drains every pending id.
    /// (The DAO binds this as a 64-bit SQLite `LIMIT`, so `Int.max` is effectively unbounded.)
    private static let unlimited = Int.max

    public init() {}

    /// Run the pass to completion (or until cancelled): enrich every pending song — or, with
    /// `folderID`, only that root's (a live reconcile's pass, which must not drain the library's
    /// pending set alongside a full pass — fix round B3) — then the end-of-pass steps (regroup
    /// albums + reap orphan facets, then reap orphan artwork).
    ///
    /// Enrichment is a CONTINUOUSLY-REFILLED bounded pool: keep `maxInFlight` extractions in
    /// flight, and as each finishes apply it serially on the actor and launch the next. A sliding
    /// window, NOT a stop-the-world per-chunk barrier — one slow file never idles the other cores
    /// waiting for a whole batch to drain. `checkCancellation` after each apply (and once more
    /// before the end-of-pass steps) makes a cancelled pass throw and skip those steps.
    public func run(
        generation: Int64, into store: LibraryStore, cache: ArtworkCache,
        extractor: some MetadataExtracting, inFolder folderID: Int64? = nil,
        progress: (@Sendable (MetadataProgress) -> Void)? = nil
    ) async throws {
        let pending = try await store.tracksNeedingMetadata(limit: Self.unlimited, inFolder: folderID)
        let maxInFlight = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 6))
        var next = 0
        try await withThrowingTaskGroup(of: ExtractResult.self) { group in
            while next < min(maxInFlight, pending.count) {
                let id = pending[next]; next += 1
                group.addTask { try await Self.extractOne(id, store: store, cache: cache, extractor: extractor) }
            }
            while let result = try await group.next() {
                try await apply(result, into: store, generation: generation)
                progress?(MetadataProgress())
                try Task.checkCancellation()
                if next < pending.count {
                    let id = pending[next]; next += 1
                    group.addTask { try await Self.extractOne(id, store: store, cache: cache, extractor: extractor) }
                }
            }
        }
        // Reached ONLY on a clean run. Albums first (regroup + reap orphan facets), then artwork
        // rows no song/album references any more, with their cache files.
        try Task.checkCancellation()
        try await store.refreshDerivedFacets()
        for orphan in try await store.sweepOrphanArtwork() {
            cache.removeFiles(cachePath: orphan.cachePath)
        }
    }

    /// Apply one result on the actor: tags+art in one transaction, or just the anti-loop marker
    /// for a file that is there but unreadable. An offline file stays pending; a gone row is
    /// skipped.
    private func apply(_ result: ExtractResult, into store: LibraryStore, generation: Int64) async throws {
        switch result.outcome {
        case let .read(metadata, artwork):
            try await store.applyExtractedResult(
                trackID: result.trackID, meta: metadata, artwork: artwork, generation: generation
            )
        case .unreadable:
            try await store.markMetadataScanned(trackID: result.trackID, generation: generation)
        case .offline, .gone:
            break
        }
    }

    /// Resolve one id's url ON the actor, then extract + cache art OFF the actor. When the
    /// extractor reads nothing, the file's presence decides: there → unreadable (marked), not
    /// there → offline (left pending). Only Sendable values cross back.
    private static func extractOne(
        _ id: Int64, store: LibraryStore, cache: ArtworkCache, extractor: some MetadataExtracting
    ) async throws -> ExtractResult {
        try Task.checkCancellation()
        guard let track = try await store.track(id: id) else {
            return ExtractResult(trackID: id, outcome: .gone)
        }
        guard let extracted = await extractor.extract(from: track.url) else {
            let present = FileManager.default.fileExists(atPath: track.url.path)
            return ExtractResult(trackID: id, outcome: present ? .unreadable : .offline)
        }
        var link: ArtworkLink?
        if let art = extracted.artwork {
            link = try? cache.store(imageData: art.data, uti: art.uti)
        }
        return ExtractResult(trackID: id, outcome: .read(extracted.metadata, link))
    }
}
