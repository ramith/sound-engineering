// MetadataScanner — the S8.3 background metadata pass (design §6).
//
// Enriches tracks that still need metadata (metadata_scanned == 0). Extraction (file
// read + parse + thumbnail) is CPU/IO-bound and runs OFF the actor in a CONTINUOUSLY-
// REFILLED bounded pool (a sliding window of at most `maxInFlight` extractions, sized to
// the M1→M5 core profile); the store WRITES serialize on the actor (one
// applyExtractedResult transaction per track). Triggered after the structural scan (NOT
// inline), reusing the scan's generation. FS-tolerant (a vanished file → extract nil →
// still marked, anti-loop), cancellable (per-task + post-apply checkCancellation; a
// cancelled pass SKIPS the end-of-pass artwork orphan sweep — no wrongful file delete on
// a partial view).

import Foundation
import LibraryStore

public struct MetadataScanner: Sendable {
    /// A per-track extraction result crossing back from the concurrent pool (Sendable).
    private struct ExtractResult {
        let trackID: Int64
        let metadata: TrackMetadata?
        let artwork: ArtworkLink?
    }

    /// `tracksNeedingMetadata` limit meaning "no limit" — the pass drains every pending id.
    /// (The DAO binds this as a 64-bit SQLite `LIMIT`, so `Int.max` is effectively unbounded.)
    private static let unlimited = Int.max

    public init() {}

    /// Run the pass to completion (or until cancelled). Pulls the pending-metadata id
    /// snapshot and enriches each in a CONTINUOUSLY-REFILLED bounded pool: keep `maxInFlight`
    /// extractions in flight, and as each finishes apply it serially on the actor and launch
    /// the next. A sliding window, NOT a stop-the-world per-chunk barrier — one slow file
    /// never idles the other cores waiting for a whole batch to drain. `checkCancellation`
    /// after each apply makes a cancelled pass throw before the end-of-pass orphan sweep.
    public func run(
        generation: Int64, into store: LibraryStore, cache: ArtworkCache,
        extractor: some MetadataExtracting,
        progress: (@Sendable (MetadataProgress) -> Void)? = nil
    ) async throws {
        let pending = try await store.tracksNeedingMetadata(limit: Self.unlimited)
        guard !pending.isEmpty else { return }
        let maxInFlight = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 6))
        var processed = 0
        var next = 0
        try await withThrowingTaskGroup(of: ExtractResult.self) { group in
            while next < min(maxInFlight, pending.count) {
                let id = pending[next]; next += 1
                group.addTask { try await Self.extractOne(id, store: store, cache: cache, extractor: extractor) }
            }
            while let result = try await group.next() {
                try await apply(result, into: store, generation: generation)
                processed += 1
                progress?(MetadataProgress(filesProcessedSoFar: processed, totalToProcess: pending.count))
                try Task.checkCancellation()
                if next < pending.count {
                    let id = pending[next]; next += 1
                    group.addTask { try await Self.extractOne(id, store: store, cache: cache, extractor: extractor) }
                }
            }
        }
        // Reached ONLY on clean completion (a cancelled pass threw above): reap artwork rows
        // no track/album references any more, and delete their cache files.
        for orphan in try await store.sweepOrphanArtwork() {
            cache.removeFiles(cachePath: orphan.cachePath)
        }
    }

    /// Apply one result on the actor: tags+art in one transaction, or just the anti-loop
    /// marker for a vanished/unreadable file (extract returned nil).
    private func apply(_ result: ExtractResult, into store: LibraryStore, generation: Int64) async throws {
        if let metadata = result.metadata {
            try await store.applyExtractedResult(
                trackID: result.trackID, meta: metadata, artwork: result.artwork, generation: generation
            )
        } else {
            try await store.markMetadataScanned(trackID: result.trackID, generation: generation)
        }
    }

    /// Resolve one id's url ON the actor, then extract + cache art OFF the actor. A row
    /// deleted since the pending snapshot resolves to a nil-metadata result (its marker
    /// UPDATE is then a harmless no-op on the missing row). Only Sendable values cross back.
    private static func extractOne(
        _ id: Int64, store: LibraryStore, cache: ArtworkCache, extractor: some MetadataExtracting
    ) async throws -> ExtractResult {
        try Task.checkCancellation()
        guard let track = try await store.track(id: id) else {
            return ExtractResult(trackID: id, metadata: nil, artwork: nil)
        }
        guard let extracted = await extractor.extract(from: track.url) else {
            return ExtractResult(trackID: id, metadata: nil, artwork: nil)
        }
        var link: ArtworkLink?
        if let art = extracted.artwork {
            link = try? cache.store(imageData: art.data, uti: art.uti)
        }
        return ExtractResult(trackID: id, metadata: extracted.metadata, artwork: link)
    }
}
